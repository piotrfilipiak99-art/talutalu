"""Coverage for the permanent GlossCache: the actual cost-prevention proof
for base languages beyond dictionary/cross-translation coverage - the same
(target_lang, lemma, base_lang) triple must only ever reach the LLM once."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import ai
from database import Base
from models import GlossCache


@pytest.fixture
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def _token(surface, lemma, pos, sentence_index=0):
    return {
        "surface": surface, "lemma": lemma, "pos": pos,
        "translation": None, "lemmaTranslation": None,
        "sentenceIndex": sentence_index,
    }


def _result(*tokens):
    body = " ".join(t["surface"] for t in tokens) + "."
    return {
        "body": body,
        "bodySentences": [{"index": 0, "charStart": 0, "charEnd": len(body)}],
        "tokens": list(tokens),
    }


def test_first_call_hits_llm_and_populates_cache(monkeypatch, db):
    calls = []

    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        calls.append(1)
        return {"g": [{"t": "to have", "l": "to have"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)

    result = _result(_token("mam", "miec", "VERB"))
    ai._fill_glosses(result, "pl", "de", db)

    assert len(calls) == 1
    assert result["tokens"][0]["lemmaTranslation"] == "to have"
    assert db.query(GlossCache).filter_by(
        target_lang="pl", lemma="miec", base_lang="de").count() == 1


def test_second_request_reuses_cache_without_calling_llm(monkeypatch, db):
    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        return {"g": [{"t": "to have", "l": "to have"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)
    ai._fill_glosses(_result(_token("mam", "miec", "VERB")), "pl", "de", db)

    def fail_if_called(*a, **k):
        raise AssertionError(
            "a cached (target, lemma, base) triple must never reach the LLM "
            "again")

    monkeypatch.setattr(ai, "_call_structured", fail_if_called)
    second = _result(_token("masz", "miec", "VERB"))
    ai._fill_glosses(second, "pl", "de", db)

    # VERB is not in _TRANSLATION_SAFE_POS, so only the lemma-level gloss is
    # reused from cache - the inflected 'translation' would need a fresh
    # LLM call, which correctly never happens here (nothing left to send).
    assert second["tokens"][0]["lemmaTranslation"] == "to have"


def test_cache_is_scoped_to_the_exact_base_language(monkeypatch, db):
    """A gloss cached for (pl, miec, de) must not leak into a request for
    (pl, miec, fr) - different base languages need their own answer."""
    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        return {"g": [{"t": "to have", "l": "to have"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)
    ai._fill_glosses(_result(_token("mam", "miec", "VERB")), "pl", "de", db)

    calls = []

    def fake_call_structured_fr(model, system, messages, schema_name, schema,
                                max_tokens):
        calls.append(1)
        return {"g": [{"t": "avoir", "l": "avoir"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured_fr)
    fr_result = _result(_token("mam", "miec", "VERB"))
    ai._fill_glosses(fr_result, "pl", "fr", db)

    assert len(calls) == 1
    assert fr_result["tokens"][0]["lemmaTranslation"] == "avoir"
