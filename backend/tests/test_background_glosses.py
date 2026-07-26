"""Coverage for the async gloss fill-in: generate-text must not block its
response on LLM glossing for words the dictionary couldn't ground - those
get scheduled as a background task and the client polls
GET /ai/generate-text/{genId}/glosses for the finished tokens."""
from types import SimpleNamespace

import pytest
from fastapi import BackgroundTasks
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import ai
from auth import get_current_user
from database import Base
from main import app


def _token(surface, lemma, pos, lemma_translation=None, sentence_index=0):
    return {
        "surface": surface, "lemma": lemma, "pos": pos,
        "translation": None, "lemmaTranslation": lemma_translation,
        "sentenceIndex": sentence_index,
    }


def _result(*tokens):
    body = " ".join(t["surface"] for t in tokens) + "."
    return {
        "body": body,
        "bodySentences": [{"index": 0, "charStart": 0, "charEnd": len(body)}],
        "tokens": list(tokens),
    }


def test_schedule_glosses_is_noop_when_everything_already_grounded():
    result = _result(_token("kot", "kot", "NOUN", lemma_translation="cat"))
    background_tasks = BackgroundTasks()

    ai._schedule_glosses(result, "pl", "en", background_tasks)

    assert result["genId"] is None
    assert background_tasks.tasks == []


def test_schedule_glosses_sets_gen_id_and_schedules_a_task_when_pending():
    result = _result(_token("pies", "pies", "NOUN"))  # ungrounded
    background_tasks = BackgroundTasks()

    ai._schedule_glosses(result, "pl", "en", background_tasks)

    assert result["genId"] is not None
    assert len(background_tasks.tasks) == 1


def test_schedule_glosses_deep_copies_so_the_response_is_never_mutated():
    result = _result(_token("pies", "pies", "NOUN"))
    background_tasks = BackgroundTasks()

    ai._schedule_glosses(result, "pl", "en", background_tasks)

    task = background_tasks.tasks[0]
    scheduled_result = task.args[1]
    assert scheduled_result is not result
    assert scheduled_result["tokens"] is not result["tokens"]


@pytest.fixture
def gloss_engine(monkeypatch):
    test_engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(test_engine)
    monkeypatch.setattr(ai, "engine", test_engine)
    return test_engine


def test_fill_glosses_background_publishes_to_gloss_results(
        monkeypatch, gloss_engine):
    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        return {"g": [{"t": "dog", "l": "dog"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)
    ai._GLOSS_RESULTS.clear()

    result = _result(_token("pies", "pies", "NOUN"))
    ai._fill_glosses_background("gen-1", result, "pl", "en")

    assert "gen-1" in ai._GLOSS_RESULTS
    _, tokens = ai._GLOSS_RESULTS["gen-1"]
    assert tokens[0]["lemmaTranslation"] == "dog"


def test_fill_glosses_background_publishes_even_on_llm_failure(
        monkeypatch, gloss_engine):
    def fail(*a, **k):
        raise RuntimeError("boom")

    monkeypatch.setattr(ai, "_call_structured", fail)
    ai._GLOSS_RESULTS.clear()

    result = _result(_token("pies", "pies", "NOUN"))
    ai._fill_glosses_background("gen-2", result, "pl", "en")

    # A background failure must still resolve the poll (otherwise the
    # client polls a genId that never resolves) - the word simply stays
    # gloss-less.
    assert "gen-2" in ai._GLOSS_RESULTS


@pytest.fixture
def client():
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=1, email="test@test.com")
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_get_glosses_not_yet_ready(client):
    res = client.get("/ai/generate-text/unknown-gen-id/glosses")
    assert res.status_code == 200
    assert res.json() == {"done": False, "tokens": None}


def test_get_glosses_ready_and_then_deleted(client):
    ai._GLOSS_RESULTS["gen-ready"] = (1e18, [{"surface": "pies"}])

    res = client.get("/ai/generate-text/gen-ready/glosses")
    assert res.status_code == 200
    assert res.json() == {"done": True, "tokens": [{"surface": "pies"}]}

    # delete-on-read: a second poll for the same genId finds nothing left.
    res2 = client.get("/ai/generate-text/gen-ready/glosses")
    assert res2.json() == {"done": False, "tokens": None}
