"""Dictionary-grounded glosses via kaikki.org/Wiktextract (Wiktionary data,
CC BY-SA - see profile_screen.dart for the required attribution).

Stage 1: target=pl, base=en only. The source data (English Wiktionary
extract) only has glosses written in English, so a lookup can only ever
help when base_lang == 'en'; every other base language keeps using the
existing pure-LLM path in ai.py untouched.

Files are hosted as GitHub Release assets (same lazy-download-on-first-use
pattern as annotate.py's UDPipe models) and read directly via sqlite3 - this
is static reference data, not user data, so it deliberately does not go
through database.py/SQLAlchemy.
"""
import os
import sqlite3
import threading
from typing import TypedDict

import httpx

DICT_PAIRS = {('pl', 'en')}  # add (target, base) tuples here to expand

DICT_DIR = os.environ.get(
    'DICTIONARY_DIR',
    os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dictionaries'))

_RELEASE_URL = (
    'https://github.com/piotrfilipiak99-art/talutalu/releases/download/'
    'dict-v1/{target}-{base}.sqlite3')

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
    os.makedirs(DICT_DIR, exist_ok=True)
    url = _RELEASE_URL.format(target=target_lang, base=base_lang)
    tmp = path + '.part'
    with httpx.stream('GET', url, follow_redirects=True, timeout=120) as r:
        r.raise_for_status()
        with open(tmp, 'wb') as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    os.replace(tmp, path)
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
