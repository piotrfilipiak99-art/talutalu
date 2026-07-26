"""Coverage for the fully-async generate-text flow: the endpoint schedules
a background job and returns a jobId in well under a second, no matter how
slow the model is - nothing here can ever hold an HTTP connection open long
enough to hit Render's reverse-proxy timeout. The client polls
GET /ai/generate-text/{jobId} through "pending" -> "textReady" (prose +
dictionary-grounded tokens, readable immediately) -> "done" (every
resolvable word glossed)."""
from types import SimpleNamespace

import annotate
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import ai
from ai import GenerateTextRequest
from auth import get_current_user
from database import Base
from main import app


def _body(**overrides):
    defaults = dict(targetLang="pl", baseLang="en", level="B1", length="Short",
                    prompt="cats", hobbies="", vocabulary=[])
    defaults.update(overrides)
    return GenerateTextRequest(**defaults)


def _token(surface, lemma, pos, lemma_translation=None, sentence_index=0,
          char_start=0, char_end=None):
    return {
        "surface": surface, "lemma": lemma, "pos": pos, "morph": {},
        "translation": None, "lemmaTranslation": lemma_translation,
        "reading": None, "root": None, "rootMeaning": None,
        "sentenceIndex": sentence_index, "charStart": char_start,
        "charEnd": char_end if char_end is not None else char_start + len(surface),
    }


@pytest.fixture
def gloss_engine(monkeypatch):
    test_engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(test_engine)
    monkeypatch.setattr(ai, "engine", test_engine)
    return test_engine


def _mock_prose(monkeypatch, sentences=None, tokens=None):
    """Stubs out the one LLM call _generate_hybrid makes for prose, and the
    local UDPipe/dictionary annotation step, so tests never touch a real
    model or a real UDPipe install."""
    sentences = sentences or [{"text": "Kot biega.", "translation": "The cat runs."}]

    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        assert schema_name == "reading_prose"
        return {"title": "Tytul", "sentences": sentences}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)
    monkeypatch.setattr(annotate, "supported", lambda lang: True)
    monkeypatch.setattr(
        annotate, "annotate_sentences",
        lambda body, spans, target, base: tokens if tokens is not None else [])


def test_run_generation_job_skips_gloss_step_when_everything_grounded(
        monkeypatch, gloss_engine):
    tokens = [_token("Kot", "kot", "NOUN", lemma_translation="cat"),
             _token("biega", "biegac", "VERB", lemma_translation="to run")]
    _mock_prose(monkeypatch, tokens=tokens)

    def fail_if_glossing(model, system, messages, schema_name, schema,
                         max_tokens):
        if schema_name == "word_glosses":
            raise AssertionError("nothing was left ungrounded - must not "
                                 "reach the LLM for glosses")
        return {"title": "Tytul", "sentences": [
            {"text": "Kot biega.", "translation": "The cat runs."}]}

    monkeypatch.setattr(ai, "_call_structured", fail_if_glossing)
    ai._JOBS.clear()

    ai._run_generation_job("job-1", _body())

    job = ai._JOBS["job-1"]
    assert job["status"] == "done"
    assert job["result"]["annotation"] == "udpipe"


def test_run_generation_job_publishes_text_ready_before_glosses_finish(
        monkeypatch, gloss_engine):
    tokens = [_token("Pies", "pies", "NOUN")]  # ungrounded
    _mock_prose(monkeypatch, tokens=tokens)
    seen_status_during_gloss_call = []

    real_fill_glosses = ai._fill_glosses

    def spying_fill_glosses(result, target, base, db):
        seen_status_during_gloss_call.append(ai._JOBS["job-2"]["status"])
        return real_fill_glosses(result, target, base, db)

    def fake_gloss_llm(model, system, messages, schema_name, schema,
                       max_tokens):
        if schema_name == "word_glosses":
            return {"g": [{"t": "dog", "l": "dog"}]}
        return {"title": "Tytul", "sentences": [
            {"text": "Pies.", "translation": "Dog."}]}

    monkeypatch.setattr(ai, "_call_structured", fake_gloss_llm)
    monkeypatch.setattr(ai, "_fill_glosses", spying_fill_glosses)
    ai._JOBS.clear()

    ai._run_generation_job("job-2", _body())

    assert seen_status_during_gloss_call == ["textReady"]
    job = ai._JOBS["job-2"]
    assert job["status"] == "done"
    assert job["result"]["tokens"][0]["lemmaTranslation"] == "dog"


def test_run_generation_job_publishes_error_status_on_failure(monkeypatch):
    def fail(*a, **k):
        raise RuntimeError("upstream boom")

    monkeypatch.setattr(ai, "_call_structured", fail)
    monkeypatch.setattr(annotate, "supported", lambda lang: True)
    ai._JOBS.clear()

    ai._run_generation_job("job-3", _body())

    job = ai._JOBS["job-3"]
    assert job["status"] == "error"


@pytest.fixture
def client():
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=1, email="test@test.com")
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_generate_text_route_returns_a_job_id_not_the_full_text(
        monkeypatch, client, gloss_engine):
    _mock_prose(monkeypatch, tokens=[
        _token("Kot", "kot", "NOUN", lemma_translation="cat")])

    res = client.post("/ai/generate-text", json={
        "targetLang": "pl", "baseLang": "en", "level": "B1",
        "length": "Short", "prompt": "cats",
    })

    assert res.status_code == 200
    body = res.json()
    assert set(body.keys()) == {"jobId"}
    assert body["jobId"]


def test_get_generation_job_unknown_id_is_404(client):
    res = client.get("/ai/generate-text/does-not-exist")
    assert res.status_code == 404


def test_get_generation_job_reaches_done_after_kickoff(
        monkeypatch, client, gloss_engine):
    # TestClient runs BackgroundTasks synchronously as part of the request
    # it was scheduled from, so by the time the kickoff call returns, the
    # job has already finished - polling right after proves the contract
    # (status + full result) even though real deployments interleave this
    # with the client's own polling loop.
    _mock_prose(monkeypatch, tokens=[
        _token("Kot", "kot", "NOUN", lemma_translation="cat")])

    kickoff = client.post("/ai/generate-text", json={
        "targetLang": "pl", "baseLang": "en", "level": "B1",
        "length": "Short", "prompt": "cats",
    })
    job_id = kickoff.json()["jobId"]

    res = client.get(f"/ai/generate-text/{job_id}")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "done"
    assert body["result"]["body"]
    assert body["result"]["tokens"][0]["lemmaTranslation"] == "cat"
