"""Proves gloss chunks for a text with many unique words (a Long text, in
practice) are fetched CONCURRENTLY rather than one-by-one - this is the fix
for Long-length generations timing out client-side (each chunk used to
wait on the previous one, compounding latency for exactly the texts with
the most unique words to gloss)."""
import time

import pytest
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


def _token(surface, lemma, pos, sentence_index=0):
    return {
        "surface": surface, "lemma": lemma, "pos": pos,
        "translation": None, "lemmaTranslation": None,
        "sentenceIndex": sentence_index,
    }


def test_multiple_chunks_are_fetched_concurrently(monkeypatch, db):
    # _GLOSS_CHUNK is 50 - 120 unique words forces 3 chunks.
    n_words = 120
    tokens = [_token(f"word{i}", f"lemma{i}", "NOUN") for i in range(n_words)]
    body = " ".join(t["surface"] for t in tokens) + "."
    result = {
        "body": body,
        "bodySentences": [{"index": 0, "charStart": 0, "charEnd": len(body)}],
        "tokens": tokens,
    }

    call_count = 0
    delay = 0.3

    def slow_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        nonlocal call_count
        call_count += 1
        time.sleep(delay)
        # Oversized on purpose - the exact count doesn't matter for this
        # test (zip() with the real chunk just ignores the extras), only
        # that every chunk clears the "not badly short" retry threshold.
        return {"g": [{"t": "x", "l": "x"} for _ in range(60)]}

    monkeypatch.setattr(ai, "_call_structured", slow_call_structured)

    start = time.monotonic()
    ai._fill_glosses(result, "pl", "en", db)
    elapsed = time.monotonic() - start

    assert call_count == 3, "120 unique words / 50 per chunk = 3 chunks"
    # Sequential would take ~3 * delay = 0.9s+; concurrent should land near
    # a single delay. Generous margin for CI/thread-scheduling variance.
    assert elapsed < delay * 2, (
        f"chunks took {elapsed:.2f}s for {call_count} calls at {delay}s "
        f"each - looks sequential, not concurrent")
