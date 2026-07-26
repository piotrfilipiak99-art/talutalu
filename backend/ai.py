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
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, Depends, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import annotate
from annotate import _TRANSLATION_SAFE_POS
from auth import get_current_user
from database import get_db
from models import GlossCache

log = logging.getLogger("talutalu.ai")

router = APIRouter(prefix="/ai")

# 'udpipe' = hybrid pipeline (LLM writes prose + glosses, UDPipe does the
# morphology deterministically); anything else = legacy all-LLM path.
# The hybrid path falls back to legacy per-request on any failure.
ANNOTATE_MODE = os.environ.get("ANNOTATE_MODE", "udpipe")

# Provider-agnostic AI config. Any OpenAI-compatible endpoint works:
#   AI_API_KEY   — the key (falls back to OPENAI_API_KEY)
#   AI_BASE_URL  — endpoint base; unset = api.openai.com
#   AI_*_MODEL   — model names per task
# reasoning_effort="minimal" is sent for OpenAI's gpt-5 family, which doesn't
# need multi-step reasoning for structured translation/glossing calls. Gemini
# 2.5 also accepts this param (as "none") through its OpenAI-compatible
# endpoint, but disabling its thinking budget was tried and measured: it
# helped short/simple generations but made Long+vocabulary ones slower, not
# faster - that case is bottlenecked by raw output-token volume, which
# thinking mode doesn't touch. Left unset for Gemini, letting it use its own
# default budget.
AI_BASE_URL = os.environ.get("AI_BASE_URL") or None
IS_OPENAI = AI_BASE_URL is None
GENERATE_MODEL = os.environ.get(
    "AI_GENERATE_MODEL", "gpt-5-mini" if IS_OPENAI else "gemini-2.5-flash-lite")
CHAT_MODEL = os.environ.get(
    "AI_CHAT_MODEL", "gpt-5-mini" if IS_OPENAI else "gemini-2.5-flash-lite")
REPAIR_MODEL = os.environ.get(
    "AI_REPAIR_MODEL", "gpt-5-nano" if IS_OPENAI else "gemini-2.5-flash-lite")

_client: OpenAI | None = None
_client_lock = threading.Lock()


def _openai() -> OpenAI:
    global _client
    key = os.environ.get("AI_API_KEY") or os.environ.get("OPENAI_API_KEY")
    if key is None:
        raise HTTPException(
            status_code=503,
            detail="AI is not configured on the server (missing AI_API_KEY)",
        )
    if _client is None:
        # Gloss chunks are now fetched concurrently (see _fill_glosses),
        # so this lazy init can genuinely race across threads on a cold
        # client - the OpenAI SDK client itself is safe for concurrent
        # requests once created, this lock only guards creating it once.
        with _client_lock:
            if _client is None:
                # The SDK's own default timeout is ~600s - a hung upstream
                # call (no error, no response) would leave a generation job
                # stuck at "pending" for up to 10 minutes with nothing for
                # the client to react to. A tighter timeout makes a hung
                # call fail fast enough for _call_structured's existing
                # retry/backoff loop to actually take over.
                _client = OpenAI(api_key=key, base_url=AI_BASE_URL,
                                 timeout=90.0)
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
        "translationSpan": {"type": ["string", "null"]},
    },
    "required": [
        "surface", "lemma", "translation", "lemmaTranslation",
        "pos", "morph", "reading", "translationSpan",
    ],
}


_TRANSIENT_MARKERS = ("429", "500", "503", "UNAVAILABLE", "overloaded",
                      "timeout", "Timeout")


def _call_structured(model: str, system: str, messages: list[dict],
                     schema_name: str, schema: dict, max_tokens: int) -> dict:
    kwargs = {"reasoning_effort": "minimal"} if IS_OPENAI else {}
    res = None
    last_error = None
    # Transient upstream hiccups get retried with growing waits — Gemini's
    # "high demand" spikes can last tens of seconds, so short retries alone
    # were observed to still lose gloss chunks.
    delays = [3, 8, 20]
    for attempt in range(4):
        try:
            log.info("ai call model=%s schema=%s attempt=%s starting",
                     model, schema_name, attempt + 1)
            res = _openai().chat.completions.create(
                model=model,
                max_completion_tokens=max_tokens,
                **kwargs,
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
            # Some providers occasionally return an empty choice — treat
            # it like any other transient failure.
            if not res.choices[0].message.content:
                last_error = RuntimeError("empty AI response")
                if attempt < len(delays):
                    log.warning("ai call model=%s schema=%s attempt=%s "
                               "returned empty content; retrying in %ss",
                               model, schema_name, attempt + 1,
                               delays[attempt])
                    res = None
                    time.sleep(delays[attempt])
                    continue
                raise HTTPException(status_code=502,
                                    detail="AI returned no content")
            break
        except HTTPException:
            raise
        except Exception as e:
            last_error = e
            # If the provider rejects reasoning_effort outright (unexpected
            # value, unsupported on this exact model) that's not a transient
            # error, but retrying instantly without it recovers instead of
            # hard-failing every call - self-healing against a bad guess.
            if "reasoning_effort" in kwargs and not any(
                    m in str(e) for m in _TRANSIENT_MARKERS):
                log.warning("reasoning_effort=%s rejected (%s); retrying "
                           "without it", kwargs["reasoning_effort"], e)
                kwargs.pop("reasoning_effort")
                continue
            if attempt < len(delays) and any(
                    m in str(e) for m in _TRANSIENT_MARKERS):
                log.warning("ai call model=%s schema=%s attempt=%s failed "
                           "(%s); retrying in %ss", model, schema_name,
                           attempt + 1, e, delays[attempt])
                time.sleep(delays[attempt])
                continue
            log.warning("ai call model=%s schema=%s attempt=%s failed "
                       "(%s); giving up", model, schema_name, attempt + 1, e)
            raise HTTPException(status_code=502,
                                detail=f"AI call failed: {e}")
    if res is None:
        log.warning("ai call model=%s schema=%s exhausted retries (%s)",
                   model, schema_name, last_error)
        raise HTTPException(status_code=502,
                            detail=f"AI call failed: {last_error}")
    content = res.choices[0].message.content
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
        trans_span = t.get("translationSpan")
        if trans_span:
            trans_span = trans_span.strip() or None
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
            "translationSpan": trans_span,
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

# Long is 10-16 (not 14-20): at C1/C2 sentence lengths, 14-20 sentences
# contradicts the Long word cap below and the model overruns it.
_LENGTH_SENTENCES = {"Short": "4-6", "Medium": "8-12", "Long": "10-16"}

# Soft word ceilings per requested length - stated in the prompt only;
# slight overruns are accepted rather than trimmed. Overridable per env.
# Long was temporarily 160 while the real bottleneck (cross_lookup's bad
# SQLite query plan - see dictionary.py) was misdiagnosed as output volume;
# restored to 220 now that that's fixed. Render's reverse-proxy timeout
# (~100s) is still a hard ceiling worth remembering if Long+vocabulary
# requests start running long again.
MAX_TEXT_WORDS = {
    "Short": int(os.environ.get("AI_MAX_WORDS_SHORT", "80")),
    "Medium": int(os.environ.get("AI_MAX_WORDS_MEDIUM", "140")),
    "Long": int(os.environ.get("AI_MAX_WORDS_LONG", "220")),
}


def _word_cap(length: str) -> int:
    return MAX_TEXT_WORDS.get(length, MAX_TEXT_WORDS["Medium"])

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


def _tokenizer_rules(target: str, base: str,
                     has_translation: bool = True) -> str:
    rules = (
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
        "(pinyin, romaji...), else null. "
    )
    if has_translation:
        rules += (
            "'translationSpan' is the exact verbatim substring of this "
            "sentence's own 'translation' field that corresponds to this "
            "word - copy it character for character, do not paraphrase - "
            "or null if this word has no clean standalone counterpart "
            "there (merged into a larger phrase, reordered beyond "
            "recognition, or omitted entirely)."
        )
    else:
        rules += "'translationSpan' is always null here."
    return rules


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
            # No sentence-level translation is given in this repair
            # prompt (just the missed words), so translationSpan can't be
            # grounded here - forced null to avoid an ungrounded guess.
            + _tokenizer_rules(target, base, has_translation=False),
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

# Deliberately terse keys: with ~100 gloss objects per text, key names
# alone were costing ~1k output tokens. 't' = inflected-form meaning,
# 'l' = lemma meaning.
_GLOSS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "g": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "t": {"type": "string"},
                    "l": {"type": "string"},
                    "s": {"type": ["string", "null"]},
                },
                "required": ["t", "l", "s"],
            },
        },
    },
    "required": ["g"],
}


_GLOSS_CHUNK = 50


def _strip_source_echo(value: str, surface: str, lemma: str) -> str:
    """The model is told never to repeat the source word in 't'/'l' - but
    it doesn't always comply, observed prefixing its answer with the
    source word anyway ("Kolesa - kola" instead of just "kola"). Strip a
    leading "<source word> <dash>" if the part before the dash is
    (almost) exactly the surface or lemma; leave everything else
    untouched, since a dash can legitimately be part of a real answer."""
    if not value:
        return value
    m = re.match(r'^\s*(.+?)\s*[—–-]\s*(.+)$', value)
    if m and m.group(1).strip().lower() in (surface.lower(), lemma.lower()):
        return m.group(2).strip()
    return value


def _apply_cache_hit(t: dict, lemma_translation: str) -> None:
    """Same convention as annotate.py's dictionary/cross_lookup grounding:
    lemmaTranslation always gets the cached value, but the inflected-form
    'translation' only does for POS classes where that's usually still
    accurate (a cached VERB lemma gloss can't stand in for its inflected
    form - see _TRANSLATION_SAFE_POS)."""
    t["lemmaTranslation"] = lemma_translation
    if t["pos"] in _TRANSLATION_SAFE_POS:
        t["translation"] = lemma_translation


def _fill_glosses(result: dict, target: str, base: str, db: Session) -> None:
    """Batched LLM glossing, tuned for token thrift:
    - each unique (surface, lemma) pair is glossed once and the result is
      copied to every occurrence (function words repeat constantly),
    - the listing groups words under their sentence, quoting each sentence
      once instead of once per word,
    - the response uses one-letter keys ('t'/'l'/'s').
    Chunks of _GLOSS_CHUNK unique words keep every call inside its output
    budget; a failed chunk degrades to gloss-less words, never an error.

    Every unique word goes through this, not just ones lacking a meaning:
    translationSpan (the word's location inside the sentence translation,
    for tap-to-highlight) can't be looked up from the dictionary or cached
    like a lemma gloss can - it depends on this exact sentence's phrasing,
    so it has to be asked fresh every time regardless of whether the
    meaning itself was already known. Meanings already grounded by
    dictionary.py or GlossCache are passed back to the model as a hint
    (see _fetch_gloss_chunk) and never overwritten by its answer here -
    only 's' is taken from the response for those words.

    Before spending any LLM tokens on a *meaning*, checks the permanent
    GlossCache (Postgres) for a (target, lemma, base) triple any earlier
    request already resolved - this is what makes non-English base
    languages affordable: every LLM answer is asked once, globally,
    forever."""
    word_tokens = [t for t in result["tokens"]
                   if re.search(r"\w", t["surface"])]
    if not word_tokens:
        return
    sents = result["bodySentences"]
    trans_sents = result["translationSentences"]
    translation = result["translation"]

    groups: dict[tuple, list] = {}
    order: list[tuple] = []
    for t in word_tokens:
        key = (t["surface"].lower(), t["lemma"].lower())
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(t)

    # Words already grounded by dictionary.py (see annotate.py) skip the
    # *meaning* lookup below - that's still the cost-saving mechanism of
    # Phase 3 - but every word, grounded or not, goes through the LLM
    # call further down to get its translationSpan.
    needing_meaning = [groups[k][0] for k in order
                       if groups[k][0]["lemmaTranslation"] is None]
    if needing_meaning:
        lemmas = {t["lemma"].lower() for t in needing_meaning}
        cached = {
            row.lemma: row.lemma_translation
            for row in db.query(GlossCache).filter(
                GlossCache.target_lang == target,
                GlossCache.base_lang == base,
                GlossCache.lemma.in_(lemmas))
        }
        for t in needing_meaning:
            hit = cached.get(t["lemma"].lower())
            if hit is not None:
                for occurrence in groups[(t["surface"].lower(),
                                         t["lemma"].lower())]:
                    _apply_cache_hit(occurrence, hit)

    all_unique = [groups[k][0] for k in order]
    # Snapshot which words already have a meaning *after* the dictionary/
    # cache pass above, so the result-applying loop below knows which
    # ones to leave alone regardless of what the model echoes back.
    already_known = {k: groups[k][0]["lemmaTranslation"] is not None
                     for k in order}

    system = (
        f"You are a bilingual dictionary: you TRANSLATE '{target}' words "
        f"into language '{base}'. All output fields must be written in "
        f"'{base}' - never repeat the '{target}' word itself. For every "
        "numbered word return exactly one triple: 't' = meaning of the "
        "exact inflected form as used in its sentence; 'l' = meaning of "
        "the dictionary (lemma) form; 's' = the exact verbatim substring "
        "of that word's 'Translation:' line (given below, alongside its "
        "'Sentence:') that corresponds to this word - copy it character "
        "for character, do not paraphrase - or null if this word has no "
        "clean standalone counterpart there (merged into a larger phrase, "
        "reordered beyond recognition, or omitted entirely). Some words "
        "carry a '[meaning: ...]' hint - that meaning is already known "
        "and authoritative, use it as-is for 't'/'l' and spend your "
        "effort locating 's'; words without a hint need 't'/'l' derived "
        "fresh. Example for target 'pl', base 'en': word 'Poszedlem' "
        "(lemma 'pojsc') in Sentence 'Poszedlem do domu.' / Translation "
        "'I went home.' -> t 'I went', l 'to go', s 'went'. Same order "
        "as the input, one triple per numbered word, no extras."
    )
    chunks = [all_unique[i:i + _GLOSS_CHUNK]
             for i in range(0, len(all_unique), _GLOSS_CHUNK)]

    # Chunks are independent LLM calls - fetching them concurrently instead
    # of one-by-one is what keeps a Long text (more unique words -> more
    # chunks) from taking minutes: each chunk still gets its own internal
    # retry, but chunks no longer wait on each other. Applying results
    # (mutating `groups`, writing GlossCache through the single `db`
    # session) stays single-threaded below - SQLAlchemy sessions aren't
    # thread-safe, so that part must not run inside the worker threads.
    if len(chunks) == 1:
        chunk_results = [_fetch_gloss_chunk(
            chunks[0], 0, sents, result["body"], trans_sents, translation,
            target, base, system)]
    else:
        with ThreadPoolExecutor(max_workers=min(len(chunks), 6)) as pool:
            chunk_results = list(pool.map(
                lambda args: _fetch_gloss_chunk(*args),
                [(chunk, i * _GLOSS_CHUNK, sents, result["body"],
                 trans_sents, translation, target, base, system)
                 for i, chunk in enumerate(chunks)]))

    for chunk_start, chunk, glosses in chunk_results:
        if glosses is None:
            continue
        if len(glosses) != len(chunk):
            log.warning("gloss chunk %s count mismatch (%s vs %s)",
                        chunk_start, len(glosses), len(chunk))
        for t, g in zip(chunk, glosses):
            key = (t["surface"].lower(), t["lemma"].lower())
            trans_span = (g.get("s") or "").strip() or None
            if trans_span is not None:
                # The model is told to copy 's' verbatim from the given
                # sentence translation or return null - but it doesn't
                # always comply (observed hallucinating a plausible-
                # looking span, e.g. "ja" for a dropped Russian pronoun,
                # that never actually appears in the given text). Enforce
                # the "verbatim or null" contract here rather than trust
                # it, since a fabricated span is worse than none - the
                # frontend would highlight nonsense with full confidence
                # instead of falling back to the whole sentence. A plain
                # substring check isn't enough either - "ja" is a
                # substring of "jak" ("as/like"), a different word
                # entirely, so this must respect word boundaries the same
                # way the frontend's own matching does.
                tsent = trans_sents[t["sentenceIndex"]]
                sent_translation = translation[tsent["charStart"]:
                                               tsent["charEnd"]]
                pattern = r'(?<!\w)' + re.escape(trans_span) + r'(?!\w)'
                if not re.search(pattern, sent_translation, re.IGNORECASE):
                    trans_span = None
                # A verbatim-but-huge answer is just as useless as a
                # hallucinated one: observed the model satisfy "copy it
                # verbatim" by echoing back most of the rest of the
                # sentence starting from the right word - technically
                # true, still the wrong answer for a single word/short
                # phrase. One source word should never need more than a
                # handful of target words.
                elif len(trans_span.split()) > 6:
                    trans_span = None
            for occurrence in groups[key]:
                occurrence["translationSpan"] = trans_span
            if already_known[key]:
                continue  # meaning is dictionary/cache-grounded - keep it
            word_translation = _strip_source_echo(
                (g["t"] or "").strip(), t["surface"], t["lemma"]) or None
            gloss = _strip_source_echo(
                (g["l"] or "").strip(), t["surface"], t["lemma"])
            # A gloss echoing the lemma or surface is useless and must not
            # reach flashcards.
            if gloss.lower() in (t["lemma"].strip().lower(),
                                 t["surface"].strip().lower()):
                gloss = ""
            for occurrence in groups[key]:
                occurrence["translation"] = word_translation
                occurrence["lemmaTranslation"] = gloss or None
            if gloss:
                db.add(GlossCache(target_lang=target, lemma=t["lemma"].lower(),
                                  base_lang=base, lemma_translation=gloss))
                try:
                    db.commit()
                except IntegrityError:
                    # Another request already cached this exact triple
                    # first (race) - their answer stands, ours is discarded.
                    db.rollback()


def _fetch_gloss_chunk(chunk: list, chunk_start: int, sents: list,
                       body: str, trans_sents: list, translation: str,
                       target: str, base: str,
                       system: str) -> tuple[int, list, list | None]:
    """The LLM-calling half of a gloss chunk - pure w.r.t. shared state (no
    `db`, no mutation of caller-owned dicts), safe to run in a worker
    thread. Returns (chunk_start, chunk, glosses) - glosses is None if the
    chunk failed outright (degrades to gloss-less words upstream, never an
    error)."""
    # Group the listing by sentence so each sentence (and its translation)
    # is quoted once. bodySentences/translationSentences share the same
    # index for freshly generated text (see _assemble), so sents[si] and
    # trans_sents[si] are the same sentence in both languages.
    by_sent: dict[int, list] = {}
    for i, t in enumerate(chunk, 1):
        by_sent.setdefault(t["sentenceIndex"], []).append((i, t))
    parts = []
    for si in sorted(by_sent):
        span = sents[si]
        tspan = trans_sents[si]
        parts.append(f'Sentence: "{body[span["charStart"]:span["charEnd"]]}"')
        parts.append(f'Translation: '
                     f'"{translation[tspan["charStart"]:tspan["charEnd"]]}"')
        for i, t in by_sent[si]:
            lemma_note = ("" if t["lemma"].lower() == t["surface"].lower()
                          else f" (lemma: {t['lemma']})")
            known = t["lemmaTranslation"] or t["translation"]
            hint = f" [meaning: {known}]" if known else ""
            parts.append(f"{i}. {t['surface']}{lemma_note}{hint}")
    listing = "\n".join(parts)
    glosses = None
    # A syntactically valid response can still be uselessly short (the
    # model bailing after a few items) - retry that like an error.
    for chunk_attempt in range(2):
        try:
            data = _call_structured(
                GENERATE_MODEL, system,
                [{"role": "user", "content":
                  f"Translate ALL {len(chunk)} numbered '{target}' "
                  f"words below into '{base}' - return exactly "
                  f"{len(chunk)} triples, covering every sentence "
                  f"group:\n{listing}"}],
                # Budget is a ceiling, not spend - generous headroom
                # so the model never truncates a chunk mid-list.
                "word_glosses", _GLOSS_SCHEMA,
                max(2500, len(chunk) * 100))
        except HTTPException as e:
            log.warning("gloss chunk %s failed (%s)", chunk_start, e.detail)
            break
        glosses = data["g"]
        if len(glosses) >= len(chunk) * 0.9:
            break
        log.warning("gloss chunk %s badly short (%s vs %s), attempt %s",
                    chunk_start, len(glosses), len(chunk), chunk_attempt + 1)
    return chunk_start, chunk, glosses


def _generate_hybrid(body: GenerateTextRequest, db: Session) -> dict:
    n_sentences = _LENGTH_SENTENCES.get(body.length, "6-10")
    system = (
        "You generate reading exercises for a language-learning app. "
        f"Write in language '{body.targetLang}' for "
        f"{_level_line(body.level)}. Give each sentence a translation "
        f"into language '{body.baseLang}'."
    )
    user_msg = (
        f"Write a text of {n_sentences} sentences, no more than "
        f"{_word_cap(body.length)} words in total. "
        + _topic_instructions(body.prompt, body.hobbies, body.vocabulary)
        + " Give it a short title in the target language."
    )
    data = _call_structured(GENERATE_MODEL, system,
                            [{"role": "user", "content": user_msg}],
                            "reading_prose", _PROSE_SCHEMA, 4000)
    result = _assemble(data["sentences"])  # sentences carry no tokens here
    result["tokens"] = annotate.annotate_sentences(
        result["body"], result["bodySentences"], body.targetLang,
        body.baseLang)
    _fill_glosses(result, body.targetLang, body.baseLang, db)
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
        f"Write a text of {n_sentences} sentences, no more than "
        f"{_word_cap(body.length)} words in total. "
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
def generate_text(body: GenerateTextRequest, user=Depends(get_current_user),
                  db: Session = Depends(get_db)):
    if ANNOTATE_MODE == "udpipe" and annotate.supported(body.targetLang):
        try:
            result = _generate_hybrid(body, db)
            result["annotation"] = "udpipe"
            return result
        except HTTPException:
            raise  # AI/auth errors are meaningful — don't mask them
        except Exception:
            log.exception("hybrid annotation failed; falling back to legacy")
    result = _generate_legacy(body)
    result["annotation"] = "llm"
    return result


# ── Analyze the learner's own text (paste-your-own in Read) ─────────────────

class AnalyzeTextRequest(BaseModel):
    body: str = Field(max_length=2000)
    targetLang: str = Field(max_length=16)
    baseLang: str = Field(max_length=16)


_ANALYZE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
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
    "required": ["sentences"],
}


def _analyze_hybrid(body: AnalyzeTextRequest, db: Session) -> dict:
    system = (
        f"You split a language learner's own '{body.targetLang}' text into "
        f"individual sentences and translate each into '{body.baseLang}'. "
        "Every 'text' must be an exact verbatim substring of the input — "
        "same words, spelling and punctuation, in order. Never paraphrase, "
        "correct, summarize or omit anything; split only on real sentence "
        "boundaries."
    )
    data = _call_structured(
        GENERATE_MODEL, system,
        [{"role": "user", "content": body.body}],
        "text_analysis", _ANALYZE_SCHEMA, max(4000, len(body.body) * 2))
    result = _assemble(data["sentences"])
    result["tokens"] = annotate.annotate_sentences(
        result["body"], result["bodySentences"], body.targetLang,
        body.baseLang)
    _fill_glosses(result, body.targetLang, body.baseLang, db)
    return result


@router.post("/analyze-text")
def analyze_text(body: AnalyzeTextRequest, user=Depends(get_current_user),
                 db: Session = Depends(get_db)):
    if not body.body.strip():
        raise HTTPException(400, "Nothing to analyze")
    if ANNOTATE_MODE != "udpipe" or not annotate.supported(body.targetLang):
        raise HTTPException(
            400, "Analysis isn't available for this language yet")
    try:
        result = _analyze_hybrid(body, db)
    except HTTPException:
        raise  # AI/auth errors are meaningful — don't mask them
    except Exception:
        log.exception("analyze-text failed")
        raise HTTPException(502, "Analysis failed")
    result["annotation"] = "udpipe"
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
def chat(body: ChatRequest, user=Depends(get_current_user),
        db: Session = Depends(get_db)):
    if ANNOTATE_MODE == "udpipe" and annotate.supported(body.targetLang):
        try:
            result = _chat_hybrid(body, db)
            result["annotation"] = "udpipe"
            return result
        except HTTPException:
            raise
        except Exception:
            log.exception("hybrid chat failed; falling back to legacy")
    result = _chat_legacy(body)
    result["annotation"] = "llm"
    return result


_CHAT_PROSE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {"text": {"type": "string"}},
    "required": ["text"],
}


def _chat_hybrid(body: ChatRequest, db: Session) -> dict:
    system = (
        "You are a friendly, encouraging language tutor inside a language-"
        f"learning app. The learner is studying '{body.targetLang}' "
        f"(their own language is '{body.baseLang}') and is "
        f"{_level_line(body.level)}.\n"
        f"Chat naturally in '{body.targetLang}', keeping replies short "
        "(1-3 sentences) and matched to the learner's level. When the "
        f"learner asks for an explanation, explain in '{body.baseLang}'."
    )
    convo = [
        {"role": "user" if m.fromUser else "assistant", "content": m.text}
        for m in body.messages[-20:]
    ]
    data = _call_structured(CHAT_MODEL, system, convo, "chat_prose",
                            _CHAT_PROSE_SCHEMA, 2000)
    text = data["text"].strip()
    # One virtual sentence spanning the whole reply: ChatMessage tokens
    # don't use sentence indices, and the gloss context is the full reply.
    spans = [{"index": 0, "charStart": 0, "charEnd": len(text)}]
    result = {
        "body": text,
        "bodySentences": spans,
        "tokens": annotate.annotate_sentences(text, spans, body.targetLang,
                                              body.baseLang),
    }
    _fill_glosses(result, body.targetLang, body.baseLang, db)
    return {"text": text, "tokens": result["tokens"]}


def _chat_legacy(body: ChatRequest) -> dict:
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
        f"'{body.baseLang}'; 'reading' only for transliteration scripts; "
        "'translationSpan' is always null (no separate translation text "
        "exists here)."
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
