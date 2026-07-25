"""Regression coverage for the cost-saving change in ai.py's
_fill_glosses(): words the dictionary already grounded (lemmaTranslation
already set by annotate.py) must never be sent to the LLM."""
import ai


def _token(surface, lemma, pos, sentence_index=0, lemma_translation=None):
    return {
        "surface": surface, "lemma": lemma, "pos": pos,
        "translation": lemma_translation, "lemmaTranslation": lemma_translation,
        "sentenceIndex": sentence_index,
    }


def test_grounded_words_are_excluded_from_llm_chunk(monkeypatch):
    body = "Kupilem kotlet i psa."
    result = {
        "body": body,
        "bodySentences": [{"index": 0, "charStart": 0, "charEnd": len(body)}],
        "tokens": [
            # already grounded by the dictionary (annotate.py would have
            # set this) - must be skipped
            _token("kotlet", "kotlet", "NOUN",
                  lemma_translation="cutlet (thin slice of meat, usually fried)"),
            # ambiguous / ungrounded - must still go to the LLM
            _token("i", "i", "CCONJ"),
            _token("psa", "pies", "NOUN"),
        ],
    }

    seen_chunks = []

    def fake_call_structured(model, system, messages, schema_name, schema,
                             max_tokens):
        seen_chunks.append(messages[0]["content"])
        # one pair per non-grounded unique word in this test
        return {"g": [{"t": "and", "l": "and"},
                     {"t": "dog", "l": "dog"}]}

    monkeypatch.setattr(ai, "_call_structured", fake_call_structured)

    ai._fill_glosses(result, "pl", "en")

    assert len(seen_chunks) == 1
    sent_text = seen_chunks[0]
    numbered_lines = [l for l in sent_text.splitlines()
                      if l[:2].rstrip(".").isdigit()]
    assert not any("kotlet" in l for l in numbered_lines), numbered_lines
    assert any("psa" in l for l in numbered_lines), numbered_lines

    tokens_by_surface = {t["surface"]: t for t in result["tokens"]}
    # untouched - dictionary's gloss must survive, not get overwritten
    assert tokens_by_surface["kotlet"]["lemmaTranslation"] == \
        "cutlet (thin slice of meat, usually fried)"
    # filled in by the (fake) LLM call
    assert tokens_by_surface["psa"]["lemmaTranslation"] == "dog"


def test_fully_grounded_text_skips_llm_entirely(monkeypatch):
    body = "Kotlet."
    result = {
        "body": body,
        "bodySentences": [{"index": 0, "charStart": 0, "charEnd": len(body)}],
        "tokens": [
            _token("Kotlet", "kotlet", "NOUN",
                  lemma_translation="cutlet (thin slice of meat, usually fried)"),
        ],
    }

    def fail_if_called(*a, **k):
        raise AssertionError("_call_structured must not be called when "
                             "every word is already dictionary-grounded")

    monkeypatch.setattr(ai, "_call_structured", fail_if_called)

    ai._fill_glosses(result, "pl", "en")  # must not raise
