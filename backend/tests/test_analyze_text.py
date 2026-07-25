"""Coverage for the /ai/analyze-text path: the learner's own pasted text
gets split/translated by the LLM, then tokenized+glossed exactly like
generated text (annotate.py + _fill_glosses), never freely rewritten."""
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

import ai
from database import Base


@pytest.fixture
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def test_analyze_text_rejects_empty_body():
    body = ai.AnalyzeTextRequest(body="   ", targetLang="pl", baseLang="en")
    try:
        # Rejected before db is ever touched - None stands in fine here.
        ai.analyze_text(body, user=None, db=None)
        assert False, "must reject an empty/whitespace-only body"
    except HTTPException as e:
        assert e.status_code == 400


def test_analyze_text_rejects_unsupported_language():
    body = ai.AnalyzeTextRequest(
        body="hello world", targetLang="xx", baseLang="en")
    try:
        ai.analyze_text(body, user=None, db=None)
        assert False, "must reject a language with no UDPipe model"
    except HTTPException as e:
        assert e.status_code == 400


def test_analyze_hybrid_splits_translates_and_tokenizes(monkeypatch, db):
    original_text = "Kupiłem kotlet. Zjadłem go."

    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        if schema_name == "text_analysis":
            # The endpoint must send the RAW pasted text as the user
            # message, unmodified, for the model to split verbatim.
            assert messages[0]["content"] == original_text
            return {"sentences": [
                {"text": "Kupiłem kotlet.",
                 "translation": "I bought a cutlet."},
                {"text": "Zjadłem go.", "translation": "I ate it."},
            ]}
        # The gloss pass for whatever the dictionary didn't already ground.
        return {"g": [{"t": "I ate", "l": "to eat"},
                     {"t": "it", "l": "it"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)

    req = ai.AnalyzeTextRequest(
        body=original_text, targetLang="pl", baseLang="en")
    result = ai._analyze_hybrid(req, db)

    assert result["body"] == original_text
    assert result["translation"] == "I bought a cutlet. I ate it."
    assert len(result["bodySentences"]) == 2
    # kotlet is single-sense in the dictionary -> grounded without the LLM.
    kotlet = next(t for t in result["tokens"]
                  if t["surface"].rstrip(".") == "kotlet")
    assert kotlet["lemmaTranslation"] is not None
