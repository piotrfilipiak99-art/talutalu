"""Dictionary-grounded glosses via kaikki.org/Wiktextract (Wiktionary data,
CC BY-SA - see profile_screen.dart for the required attribution).

Stage 1 (`lookup`): target=pl, base=en only. The source data (English
Wiktionary extract) only has glosses written in English, so this lookup can
only ever help when base_lang == 'en'.

Stage 2 (`cross_lookup`): language-agnostic. English Wiktionary entries
carry a translations table per sense (e.g. the "guy, fellow" sense of "cat"
lists French "mec"/"gus", Portuguese "cara"/"rapaz", Spanish "tio"/"tipo").
Grouping every sense's translations together lets ONE build ground ANY
(target_lang, base_lang) pair the data covers, not just pl->en - see
backend/scripts/build_cross_translations.py. Whatever neither lookup nor
cross_lookup can resolve falls through to the LLM in ai.py, cached
permanently in Postgres (GlossCache) so the same word is never asked twice.

Files are hosted as GitHub Release assets (same lazy-download-on-first-use
pattern as annotate.py's UDPipe models) and read directly via sqlite3 - this
is static reference data, not user data, so it deliberately does not go
through database.py/SQLAlchemy.
"""
import logging
import os
import sqlite3
import threading
import time
from typing import TypedDict

import httpx

log = logging.getLogger("talutalu.dictionary")

DICT_PAIRS = {('pl', 'en')}  # add (target, base) tuples here to expand

DICT_DIR = os.environ.get(
    'DICTIONARY_DIR',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dictionaries'))

_RELEASE_URL = (
    'https://github.com/piotrfilipiak99-art/talutalu/releases/download/'
    'dict-v1/{target}-{base}.sqlite3')

_CROSS_ASSET = 'cross_translations.sqlite3'
_CROSS_RELEASE_URL = (
    'https://github.com/piotrfilipiak99-art/talutalu/releases/download/'
    f'dict-v1/{_CROSS_ASSET}')

# UD POS tag -> acceptable Wiktextract POS strings. Used to disambiguate
# homonyms across parts of speech; if filtering yields nothing we retry
# unfiltered rather than dropping the word entirely.
UD_TO_WIKTEXTRACT = {
    'NOUN': {'noun'}, 'VERB': {'verb'}, 'ADJ': {'adj'}, 'ADV': {'adv'},
    'PROPN': {'name'}, 'NUM': {'num'}, 'DET': {'det', 'pron'},
    'PRON': {'pron'}, 'ADP': {'prep', 'postp'},
    'CCONJ': {'conj'}, 'SCONJ': {'conj'}, 'INTJ': {'intj'},
}

_conns: dict[tuple, sqlite3.Connection] = {}
_lock = threading.Lock()


def supported(target_lang: str, base_lang: str) -> bool:
    return (target_lang, base_lang) in DICT_PAIRS


def _db_path(target_lang: str, base_lang: str) -> str:
    return os.path.join(DICT_DIR, f'{target_lang}-{base_lang}.sqlite3')


def _download(target_lang: str, base_lang: str) -> str:
    path = _db_path(target_lang, base_lang)
    if os.path.exists(path):
        return path
    # This runs synchronously inside the request that first needs this pair
    # (e.g. right after a fresh deploy wipes Render's ephemeral disk) and
    # used to be completely silent - a slow/stalled download here looked
    # identical to a hung AI call from the outside. Log start/end so it's
    # distinguishable.
    log.info("downloading dictionary %s-%s (first use since last deploy/"
             "restart)", target_lang, base_lang)
    start = time.monotonic()
    os.makedirs(DICT_DIR, exist_ok=True)
    url = _RELEASE_URL.format(target=target_lang, base=base_lang)
    tmp = path + '.part'
    with httpx.stream('GET', url, follow_redirects=True, timeout=120) as r:
        r.raise_for_status()
        with open(tmp, 'wb') as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    os.replace(tmp, path)
    log.info("downloaded dictionary %s-%s in %.1fs (%d bytes)",
             target_lang, base_lang, time.monotonic() - start,
             os.path.getsize(path))
    return path


def _get_conn(target_lang: str, base_lang: str) -> sqlite3.Connection:
    key = (target_lang, base_lang)
    with _lock:
        conn = _conns.get(key)
        if conn is not None:
            return conn
    path = _download(target_lang, base_lang)
    conn = sqlite3.connect(f'file:{path}?mode=ro', uri=True,
                           check_same_thread=False)
    with _lock:
        _conns[key] = conn
    return conn


class DictEntry(TypedDict):
    senses: list[str]
    root: str | None
    rootMeaning: str | None


def _query(conn: sqlite3.Connection, lemma: str, wiktextract_pos: set[str] | None):
    # check_same_thread=False only lets a connection be reused across
    # threads - it does not make concurrent execute() calls from different
    # threads safe. FastAPI runs concurrent requests on different worker
    # threads even in a single process, so without this lock two requests
    # querying at once could corrupt the shared connection (observed in
    # production as "sqlite3.InterfaceError: bad parameter or other API
    # misuse"). Queries are local/fast (no LLM calls), so serializing them
    # is cheap.
    with _lock:
        cur = conn.cursor()
        if wiktextract_pos:
            placeholders = ','.join('?' * len(wiktextract_pos))
            cur.execute(
                f'SELECT gloss, root, root_meaning FROM entries '
                f'WHERE lemma = ? AND pos IN ({placeholders}) '
                f'ORDER BY sense_rank',
                (lemma, *wiktextract_pos))
        else:
            cur.execute(
                'SELECT gloss, root, root_meaning FROM entries '
                'WHERE lemma = ? ORDER BY sense_rank',
                (lemma,))
        return cur.fetchall()


def lookup(lemma: str, pos: str, target_lang: str,
          base_lang: str) -> DictEntry | None:
    """None if the pair is unsupported or the lemma has no entry. Callers
    must treat len(senses) > 1 as ambiguous - this function does not
    disambiguate, it just returns what the dictionary has."""
    if not supported(target_lang, base_lang):
        return None
    conn = _get_conn(target_lang, base_lang)
    lemma = lemma.lower().strip()
    if not lemma:
        return None
    wiktextract_pos = UD_TO_WIKTEXTRACT.get(pos)
    rows = _query(conn, lemma, wiktextract_pos)
    if not rows and wiktextract_pos:
        rows = _query(conn, lemma, None)
    if not rows:
        return None
    senses = [r[0] for r in rows]
    root, root_meaning = rows[0][1], rows[0][2]
    return {'senses': senses, 'root': root, 'rootMeaning': root_meaning}


# ── Cross-language translations (Stage 2) ───────────────────────────────────

_cross_conn: sqlite3.Connection | None = None
_cross_lock = threading.Lock()


def _cross_db_path() -> str:
    return os.path.join(DICT_DIR, _CROSS_ASSET)


def _download_cross() -> str:
    path = _cross_db_path()
    if os.path.exists(path):
        return path
    # See _download()'s comment - same silent-blocking hazard, and this
    # file is the bigger of the two (~120MB uncompressed).
    log.info("downloading cross-translation index (first use since last "
             "deploy/restart)")
    start = time.monotonic()
    os.makedirs(DICT_DIR, exist_ok=True)
    tmp = path + '.part'
    with httpx.stream('GET', _CROSS_RELEASE_URL, follow_redirects=True,
                      timeout=120) as r:
        r.raise_for_status()
        with open(tmp, 'wb') as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    os.replace(tmp, path)
    log.info("downloaded cross-translation index in %.1fs (%d bytes)",
             time.monotonic() - start, os.path.getsize(path))
    return path


def _get_cross_conn() -> sqlite3.Connection:
    global _cross_conn
    with _cross_lock:
        if _cross_conn is not None:
            return _cross_conn
    path = _download_cross()
    conn = sqlite3.connect(f'file:{path}?mode=ro', uri=True,
                           check_same_thread=False)
    with _cross_lock:
        _cross_conn = conn
    return _cross_conn


def cross_lookup(lemma: str, target_lang: str,
                 base_lang: str) -> str | list[str] | None:
    """None if no translation group contains [lemma] in [target_lang]; a
    single str if exactly one candidate word exists for [base_lang] across
    every matching group (safe to use); a list of 2+ distinct candidates if
    ambiguous - the caller must not auto-fill in that case, same convention
    as lookup()'s multi-sense list."""
    conn = _get_cross_conn()
    lemma = lemma.lower().strip()
    if not lemma:
        return None
    # Same concurrency hazard as _query() above - see its comment.
    with _cross_lock:
        cur = conn.execute(
            'SELECT DISTINCT m2.word FROM members m1 '
            'JOIN members m2 ON m1.group_id = m2.group_id '
            'WHERE m1.lang_code = ? AND m1.word = ? AND m2.lang_code = ?',
            (target_lang, lemma, base_lang))
        words = [r[0] for r in cur.fetchall()]
    if not words:
        return None
    return words[0] if len(words) == 1 else words
