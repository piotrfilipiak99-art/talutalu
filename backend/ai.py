"""AI endpoints backed by OpenAI gpt-5-nano.

The model returns *structure* (sentences -> tokens with lemma/POS/morph/
glosses); character offsets are computed here by walking the assembled
strings, because LLMs cannot be trusted to count characters. root/
rootMeaning are deliberately left null — per project policy they must come
from a real dictionary source (RAG), not free generation.
"""
import json
import logging
import os
import re

from fastapi import APIRouter, Depends, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

import annotate
from auth import get_current_user

log = logging.getLogger("talutalu.ai")

router = APIRouter(prefix="/ai")

# 'udpipe' = hybrid pipeline (LLM writes prose + glosses, UDPipe does the
# morphology deterministically); anything else = legacy all-LLM path.
# The hybrid path falls back to legacy per-request on any failure.
ANNOTATE_MODE = os.environ.get("ANNOTATE_MODE", "udpipe")

# Per-task models: prose quality matters most where the output is durable
# (reading texts) or user-facing (chat), so those default to gpt-5-mini.
# The token-repair pass is a mechanical dictionary task — nano is enough.
# All overridable per environment without a code change.
GENERATE_MODEL = os.environ.get("AI_GENERATE_MODEL", "gpt-5-mini")
CHAT_MODEL = os.environ.get("AI_CHAT_MODEL", "gpt-5-mini")
REPAIR_MODEL = os.environ.get("AI_REPAIR_MODEL", "gpt-5-nano")

_client: OpenAI | None = None


def _openai() -> OpenAI:
    global _client
    if os.environ.get("OPENAI_API_KEY") is None:
        raise HTTPException(
            status_code=503,
            detail="AI is not configured on the server (missing OPENAI_API_KEY)",
        )
    if _client is None:
        _client = OpenAI()
    return _client


# ── Shared token schema (strict structured outputs: no free-form maps) ──────

_TOKEN_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "surface": {"type": "string"},
        "lemma": {"type": "string"},
        "translation": {"type": ["string", "null"]},
        "lemmaTranslation": {"type": ["string", "null"]},
        "pos": {"type": "string"},
        "morph": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "feature": {"type": "string"},
                    "value": {"type": "string"},
                },
                "required": ["feature", "value"],
            },
        },
        "reading": {"type": ["string", "null"]},
    },
    "required": [
        "surface", "lemma", "translation", "lemmaTranslation",
        "pos", "morph", "reading",
    ],
}


def _call_structured(model: str, system: str, messages: list[dict],
                     schema_name: str, schema: dict, max_tokens: int) -> dict:
    try:
        res = _openai().chat.completions.create(
            model=model,
            reasoning_effort="minimal",
            max_completion_tokens=max_tokens,
            messages=[{"role": "system", "content": system}, *messages],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": schema_name,
                    "strict": True,
                    "schema": schema,
                },
            },
        )
    except HTTPException:
        raise
    except Exception as e:  # network, quota, auth — surface a readable error
        raise HTTPException(status_code=502, detail=f"AI call failed: {e}")
    content = res.choices[0].message.content
    if not content:
        raise HTTPException(status_code=502, detail="AI returned no content")
    if res.usage:
        log.info("ai call model=%s schema=%s in=%s out=%s", model,
                 schema_name, res.usage.prompt_tokens,
                 res.usage.completion_tokens)
    return json.loads(content)


def _tokens_with_offsets(sentence_tokens, text: str, sent_start: int,
                         sent_index: int) -> list[dict]:
    """Locate each token's surface in [text] scanning forward from the
    sentence start; tokens the model hallucinated (not present verbatim)
    are dropped rather than guessed."""
    out = []
    cursor = sent_start
    for t in sentence_tokens:
        surface = t["surface"]
        pos = text.find(surface, cursor)
        if pos == -1:
            continue
        cursor = pos + len(surface)
        # The model occasionally echoes the target-language lemma into
        # lemmaTranslation instead of glossing it (seen in the wild:
        # lemma "zajęcie", lemmaTranslation "zajęcie"). A gloss identical
        # to the word it glosses is never useful — drop it so clients fall
        # back to the inflected-form translation.
        lemma_gloss = t["lemmaTranslation"]
        if lemma_gloss and lemma_gloss.strip().lower() in (
                t["lemma"].strip().lower(), surface.strip().lower()):
            lemma_gloss = None
        out.append({
            "surface": surface,
            "lemma": t["lemma"],
            "translation": t["translation"],
            "lemmaTranslation": lemma_gloss,
            "pos": t["pos"],
            "morph": {m["feature"]: m["value"] for m in t["morph"]},
            "reading": t["reading"],
            "root": None,          # reserved for dictionary-grounded data
            "rootMeaning": None,   # (never free-generated by the model)
            "sentenceIndex": sent_index,
            "charStart": pos,
            "charEnd": cursor,
        })
    return out


# ── Text generation (Read tab) ───────────────────────────────────────────────


class GenerateTextRequest(BaseModel):
    targetLang: str = Field(max_length=16)
    baseLang: str = Field(max_length=16)
    level: str = Field(default="", max_length=32)     # e.g. A2, B1
    length: str = Field(default="", max_length=32)    # Short / Medium / Long
    prompt: str = Field(default="", max_length=500)
    hobbies: str = Field(default="", max_length=200)
    vocabulary: list[str] = Field(default=[], max_length=30)


_GENERATE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "title": {"type": "string"},
        "sentences": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "text": {"type": "string"},
                    "translation": {"type": "string"},
                    "tokens": {"type": "array", "items": _TOKEN_SCHEMA},
                },
                "required": ["text", "translation", "tokens"],
            },
        },
    },
    "required": ["title", "sentences"],
}

_LENGTH_SENTENCES = {"Short": "4-6", "Medium": "8-12", "Long": "14-20"}

# A bare label like "B1" barely changes what a small model writes — spell
# out what each CEFR band means so the difficulty knob actually turns.
_LEVEL_GUIDANCE = {
    "A1": "absolute beginner: use ONLY the most common everyday words, very "
          "short simple sentences (4-8 words), present tense, no subordinate "
          "clauses",
    "A2": "elementary: high-frequency vocabulary, short sentences, simple "
          "past and future allowed, at most one subordinate clause per "
          "sentence",
    "B1": "intermediate: everyday vocabulary, medium-length sentences, "
          "common connectors, occasional subordinate clauses",
    "B2": "upper-intermediate: broader vocabulary including some abstract "
          "terms, complex sentences with multiple clauses, full range of "
          "tenses and aspect",
    "C1": "advanced: rich, precise, idiomatic vocabulary, long complex "
          "sentences, nuanced grammar and varied register",
    "C2": "near-native: sophisticated literary or academic language, idioms, "
          "rare vocabulary, elaborate syntax",
}


def _level_line(level: str) -> str:
    guidance = _LEVEL_GUIDANCE.get(level)
    if guidance is None:
        return f"a learner whose level is '{level or 'intermediate'}'"
    return (f"a learner at CEFR {level} — {guidance}. Matching this "
            "difficulty is the most important constraint")


def _tokenizer_rules(target: str, base: str) -> str:
    return (
        "Tokenize EVERY word and punctuation mark of each sentence, in "
        "order — no word may be skipped. Each token's 'surface' must appear "
        "verbatim in the sentence text. Use Universal Dependencies POS tags "
        "(NOUN, VERB, ADJ, PRON, ADP, PUNCT, ...) and UD morph features "
        "(Case, Number, Gender, Person, Tense, Aspect, Mood, ...). "
        f"'translation' glosses the exact inflected form in '{base}' and is "
        "REQUIRED for every word token (null only for punctuation); "
        f"'lemmaTranslation' glosses the dictionary form, also in '{base}' — "
        f"it must NEVER contain a '{target}' word or repeat the lemma. "
        "Set 'reading' only for scripts needing transliteration "
        "(pinyin, romaji...), else null."
    )


def _assemble(sentences: list[dict]) -> dict:
    """Join model sentences into body/translation strings and compute all
    character offsets deterministically."""
    body_parts, trans_parts = [], []
    body_sents, trans_sents, tokens = [], [], []
    b_cursor = t_cursor = 0
    kept = []
    for s in sentences:
        text, trans = s["text"].strip(), s["translation"].strip()
        if not text:
            continue
        i = len(kept)
        if body_parts:
            b_cursor += 1  # joining space
            t_cursor += 1
        body_sents.append({"index": i, "charStart": b_cursor,
                           "charEnd": b_cursor + len(text),
                           "alignsToIndex": None})
        trans_sents.append({"index": i, "charStart": t_cursor,
                            "charEnd": t_cursor + len(trans),
                            "alignsToIndex": i})
        body_parts.append(text)
        trans_parts.append(trans)
        b_cursor += len(text)
        t_cursor += len(trans)
        kept.append(s)

    full_body = " ".join(body_parts)
    for i, s in enumerate(kept):
        tokens.extend(_tokens_with_offsets(
            s.get("tokens", []), full_body, body_sents[i]["charStart"], i))

    return {
        "body": full_body,
        "translation": " ".join(trans_parts),
        "tokens": tokens,
        "bodySentences": body_sents,
        "translationSentences": trans_sents,
    }


_REPAIR_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {"tokens": {"type": "array", "items": _TOKEN_SCHEMA}},
    "required": ["tokens"],
}


def _repair_coverage(result: dict, target: str, base: str) -> None:
    """Every word the user taps must answer — find word spans no token
    covers (model skipped them or hallucinated a differing surface) and
    annotate just those with one extra, small model call."""
    body = result["body"]
    covered = bytearray(len(body))
    for t in result["tokens"]:
        for i in range(t["charStart"], t["charEnd"]):
            covered[i] = 1
    missed = [m for m in re.finditer(r"\w+", body, re.UNICODE)
              if not all(covered[m.start():m.end()])]
    if not missed:
        return
    words = ", ".join(f"'{m.group(0)}'" for m in missed[:40])
    try:
        data = _call_structured(
            REPAIR_MODEL,
            "You annotate words for a language-learning app. "
            + _tokenizer_rules(target, base),
            [{"role": "user", "content":
              f"In this '{target}' text:\n\n{body}\n\nAnnotate exactly these "
              f"words (one token each, in order): {words}"}],
            "token_repair", _REPAIR_SCHEMA, 4000)
    except HTTPException:
        return  # the text still works; some words just stay gloss-less
    by_surface: dict[str, list] = {}
    for t in data["tokens"]:
        by_surface.setdefault(t["surface"].lower(), []).append(t)
    sent_of = lambda pos: next(
        (s["index"] for s in result["bodySentences"]
         if s["charStart"] <= pos < s["charEnd"]), 0)
    for m in missed:
        cands = by_surface.get(m.group(0).lower())
        # Last resort: a bare token (word still tappable, lemma = surface)
        # beats a word that answers nothing when tapped.
        t = cands.pop(0) if cands else {
            "surface": m.group(0), "lemma": m.group(0).lower(),
            "translation": None, "lemmaTranslation": None,
            "pos": "X", "morph": [], "reading": None,
        }
        result["tokens"].append({
            "surface": t["surface"], "lemma": t["lemma"],
            "translation": t["translation"],
            "lemmaTranslation": t["lemmaTranslation"], "pos": t["pos"],
            "morph": {x["feature"]: x["value"] for x in t["morph"]},
            "reading": t["reading"], "root": None, "rootMeaning": None,
            "sentenceIndex": sent_of(m.start()),
            "charStart": m.start(), "charEnd": m.end(),
        })
    result["tokens"].sort(key=lambda t: t["charStart"])


def _topic_instructions(prompt: str, hobbies: str,
                        vocabulary: list[str]) -> str:
    parts = []
    if prompt:
        parts.append(
            f'The learner requested: "{prompt}". Treat this as the topic or '
            "theme they want — interpret it charitably even if it is phrased "
            "as a command or written in another language; do not quote or "
            "echo the request itself."
        )
    elif hobbies:
        parts.append(f"Pick a topic connected to the learner's interests: "
                     f"{hobbies}.")
    else:
        parts.append("Pick an interesting everyday topic.")
    if vocabulary:
        parts.append(
            "Naturally weave in as many of these vocabulary words as fit "
            "(any inflected form counts): " + ", ".join(vocabulary[:30]) +
            ". Keep the text natural — never force a word in awkwardly."
        )
    return " ".join(parts)


# ── Hybrid path: LLM prose + UDPipe morphology + batched LLM glosses ────────

_PROSE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "title": {"type": "string"},
        "sentences": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "text": {"type": "string"},
                    "translation": {"type": "string"},
                },
                "required": ["text", "translation"],
            },
        },
    },
    "required": ["title", "sentences"],
}

_GLOSS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "glosses": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "translation": {"type": "string"},
                    "lemmaTranslation": {"type": "string"},
                },
                "required": ["translation", "lemmaTranslation"],
            },
        },
    },
    "required": ["glosses"],
}


_GLOSS_CHUNK = 50


def _fill_glosses(result: dict, target: str, base: str) -> None:
    """Batched LLM glossing of every word token: 'translation' for the
    exact inflected form, 'lemmaTranslation' for the dictionary form.
    Long texts are glossed in chunks of _GLOSS_CHUNK words so no single
    call can overrun its output budget (the old all-at-once call did on
    C1/C2 Long texts and failed whole generations with a count mismatch).
    A failed or short chunk degrades to gloss-less tokens instead of
    failing the request - the text is still fully usable."""
    word_tokens = [t for t in result["tokens"]
                   if re.search(r"\w", t["surface"])]
    if not word_tokens:
        return
    sents = result["bodySentences"]
    system = (
        f"You are a bilingual dictionary: you TRANSLATE '{target}' words "
        f"into language '{base}'. Both output fields must be written in "
        f"'{base}' - never repeat the '{target}' word itself. For every "
        "numbered word return exactly one pair: 'translation' = meaning of "
        "the exact inflected form as used in its sentence; "
        "'lemmaTranslation' = meaning of the dictionary (lemma) form. "
        "Example for target 'pl', base 'en': word 'Poszedlem' (lemma "
        "'pojsc') -> translation 'I went', lemmaTranslation 'to go'. "
        "Same order as the input, one pair per numbered word, no extras."
    )
    for chunk_start in range(0, len(word_tokens), _GLOSS_CHUNK):
        chunk = word_tokens[chunk_start:chunk_start + _GLOSS_CHUNK]
        listing = "\n".join(
            f"{i+1}. {t['surface']} (lemma: {t['lemma']}, sentence: "
            f"\"{result['body'][sents[t['sentenceIndex']]['charStart']:sents[t['sentenceIndex']]['charEnd']]}\")"
            for i, t in enumerate(chunk))
        try:
            data = _call_structured(
                GENERATE_MODEL, system,
                [{"role": "user", "content":
                  f"Translate these '{target}' words into '{base}':\n"
                  f"{listing}"}],
                "word_glosses", _GLOSS_SCHEMA,
                max(2000, len(chunk) * 60))
            glosses = data["glosses"]
        except HTTPException:
            log.warning("gloss chunk %s failed; words left unglossed",
                        chunk_start)
            continue
        if len(glosses) != len(chunk):
            log.warning("gloss chunk %s count mismatch (%s vs %s)",
                        chunk_start, len(glosses), len(chunk))
        for t, g in zip(chunk, glosses):
            t["translation"] = g["translation"] or None
            gloss = (g["lemmaTranslation"] or "").strip()
            # A gloss echoing the lemma or surface is useless and must not
            # reach flashcards.
            if gloss.lower() in (t["lemma"].strip().lower(),
                                 t["surface"].strip().lower()):
                gloss = ""
            t["lemmaTranslation"] = gloss or None


def _generate_hybrid(body: GenerateTextRequest) -> dict:
    n_sentences = _LENGTH_SENTENCES.get(body.length, "6-10")
    system = (
        "You generate reading exercises for a language-learning app. "
        f"Write in language '{body.targetLang}' for "
        f"{_level_line(body.level)}. Give each sentence a translation "
        f"into language '{body.baseLang}'."
    )
    user_msg = (
        f"Write a text of {n_sentences} sentences. "
        + _topic_instructions(body.prompt, body.hobbies, body.vocabulary)
        + " Give it a short title in the target language."
    )
    data = _call_structured(GENERATE_MODEL, system,
                            [{"role": "user", "content": user_msg}],
                            "reading_prose", _PROSE_SCHEMA, 4000)
    result = _assemble(data["sentences"])  # sentences carry no tokens here
    result["tokens"] = annotate.annotate_sentences(
        result["body"], result["bodySentences"], body.targetLang)
    _fill_glosses(result, body.targetLang, body.baseLang)
    result["title"] = data["title"]
    return result


def _generate_legacy(body: GenerateTextRequest) -> dict:
    n_sentences = _LENGTH_SENTENCES.get(body.length, "6-10")
    system = (
        "You generate reading exercises for a language-learning app. "
        f"Write in language '{body.targetLang}' for "
        f"{_level_line(body.level)}. Sentence-by-sentence translations "
        f"go into language '{body.baseLang}'.\n" +
        _tokenizer_rules(body.targetLang, body.baseLang)
    )
    user_msg = (
        f"Write a text of {n_sentences} sentences. "
        + _topic_instructions(body.prompt, body.hobbies, body.vocabulary)
        + " Give it a short title in the target language."
    )
    data = _call_structured(GENERATE_MODEL, system,
                            [{"role": "user", "content": user_msg}],
                            "reading_text", _GENERATE_SCHEMA, 16000)
    result = _assemble(data["sentences"])
    _repair_coverage(result, body.targetLang, body.baseLang)
    result["title"] = data["title"]
    return result


@router.post("/generate-text")
def generate_text(body: GenerateTextRequest, user=Depends(get_current_user)):
    if ANNOTATE_MODE == "udpipe" and annotate.supported(body.targetLang):
        try:
            result = _generate_hybrid(body)
            result["annotation"] = "udpipe"
            return result
        except HTTPException:
            raise  # AI/auth errors are meaningful — don't mask them
        except Exception:
            log.exception("hybrid annotation failed; falling back to legacy")
    result = _generate_legacy(body)
    result["annotation"] = "llm"
    return result


# ── Deck generation (Flashcards tab) ─────────────────────────────────────────


class GenerateDeckRequest(BaseModel):
    targetLang: str = Field(max_length=16)
    baseLang: str = Field(max_length=16)
    level: str = Field(default="", max_length=32)
    topic: str = Field(max_length=200)
    count: int = Field(ge=1, le=50)
    kind: str = Field(default="vocab", pattern="^(vocab|phrases)$")


_DECK_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "word": {"type": "string"},
                    "translation": {"type": "string"},
                    "wordType": {"type": ["string", "null"]},
                },
                "required": ["word", "translation", "wordType"],
            },
        },
    },
    "required": ["items"],
}


@router.post("/generate-deck")
def generate_deck(body: GenerateDeckRequest, user=Depends(get_current_user)):
    if body.kind == "phrases":
        what = (
            "short, genuinely useful everyday phrases or expressions "
            "(2-6 words each, e.g. set phrases, collocations, functional "
            "chunks people actually say). Set 'wordType' to 'phrase' for "
            "every item."
        )
    else:
        what = (
            "single vocabulary words in their dictionary (base) form. Set "
            "'wordType' to one of: noun, verb, adjective, adverb, other."
        )
    system = (
        "You build flashcard decks for a language-learning app. Generate "
        f"items in language '{body.targetLang}' for "
        f"{_level_line(body.level)}. 'translation' is the meaning in "
        f"language '{body.baseLang}'. Produce {what} No duplicates, no "
        "numbering inside values."
    )
    user_msg = (
        f"Generate exactly {body.count} items on the topic: "
        f"\"{body.topic}\"."
    )
    data = _call_structured(GENERATE_MODEL, system,
                            [{"role": "user", "content": user_msg}],
                            "deck_items", _DECK_SCHEMA, 6000)
    # Dedupe case-insensitively and cap at the requested count.
    seen: set[str] = set()
    items = []
    for it in data["items"]:
        key = it["word"].strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        items.append({
            "word": it["word"].strip(),
            "translation": it["translation"].strip(),
            "wordType": (it["wordType"] or "").strip().lower() or None,
        })
        if len(items) >= body.count:
            break
    return {"items": items}


# ── Chat replies (Converse tab) ──────────────────────────────────────────────


class ChatTurn(BaseModel):
    fromUser: bool
    text: str = Field(max_length=4000)


class ChatRequest(BaseModel):
    targetLang: str = Field(max_length=16)
    baseLang: str = Field(max_length=16)
    level: str = Field(default="", max_length=32)
    messages: list[ChatTurn]  # server uses the most recent turns only


_CHAT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "text": {"type": "string"},
        "tokens": {"type": "array", "items": _TOKEN_SCHEMA},
    },
    "required": ["text", "tokens"],
}


@router.post("/chat")
def chat(body: ChatRequest, user=Depends(get_current_user)):
    system = (
        "You are a friendly, encouraging language tutor inside a language-"
        f"learning app. The learner is studying '{body.targetLang}' "
        f"(their own language is '{body.baseLang}') and is "
        f"{_level_line(body.level)}.\n"
        f"Chat naturally in '{body.targetLang}', keeping replies short "
        "(1-3 sentences) and matched to the learner's level. When the "
        f"learner asks for an explanation, explain in '{body.baseLang}'.\n"
        f"Tokenize every '{body.targetLang}' word and punctuation mark of "
        "your reply, in order, each 'surface' verbatim as it appears; skip "
        f"'{body.baseLang}' words entirely. Universal Dependencies POS tags "
        "and morph features; 'translation'/'lemmaTranslation' gloss into "
        f"'{body.baseLang}'; 'reading' only for transliteration scripts."
    )
    convo = [
        {"role": "user" if m.fromUser else "assistant", "content": m.text}
        for m in body.messages[-20:]
    ]
    data = _call_structured(CHAT_MODEL, system, convo, "chat_reply",
                            _CHAT_SCHEMA, 8000)

    text = data["text"]
    return {
        "text": text,
        "tokens": _tokens_with_offsets(data["tokens"], text, 0, 0),
    }
