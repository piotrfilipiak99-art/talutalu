#!/usr/bin/env python3
"""One-time, manual, offline build of a language-agnostic cross-translation
index from kaikki.org's English-headword extract. NOT part of the FastAPI
runtime - run this locally, then upload the resulting .sqlite3 as a second
GitHub Release asset (see backend/dictionary.py for the download side).

Unlike build_dictionary.py (one target language -> English glosses only),
this reads the ENGLISH entries themselves, which carry a 'translations' list
per sense (e.g. the "guy, fellow" sense of "cat" lists Danish "fyr", Finnish
"kundi"/"heppu", French "mec"/"gus", Portuguese "cara"/"rapaz", Spanish
"tio"). Grouping every sense's translations together lets one build ground
ANY (target_lang, base_lang) pair the data covers, not just one pair - see
dictionary.py's cross_lookup().

Usage:
    python build_cross_translations.py                  # full build (~3.2GB source)
    python build_cross_translations.py --sample 50000    # smoke test

License: Wiktionary content, CC BY-SA - same attribution as build_dictionary.py
(Tatu Ylonen: Wiktextract: Wiktionary as Machine-Readable Structured Data,
LREC 2018), reproduced in the app's profile screen.
"""
import argparse
import json
import os
import sqlite3
import sys

import httpx

DEFAULT_URL = 'https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl'

# Only the app's current target languages - cross_lookup() is never called
# with anything outside this set, so keeping only these bounds the output
# size and skips ~130 languages of irrelevant Wiktionary translation data.
APP_LANGS = {'pl', 'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'uk', 'ja', 'ko',
            'zh', 'ar', 'nl', 'sv', 'tr', 'cs', 'el', 'hi'}

# Wiktionary's translation tables use finer-grained codes than our app for
# some languages. 'cmn' (Mandarin) is the dominant Chinese code in the data
# (far more common than 'zh' itself) and maps to our 'zh'. 'yue' (Cantonese)
# is a DIFFERENT, not mutually intelligible language and must never be
# merged in - it's simply dropped (not in APP_LANGS after normalization).
NORMALIZE = {'cmn': 'zh'}


def _iter_lines(url: str, sample: int | None):
    """Yields raw JSON lines, streaming straight off the HTTP response - no
    temp file, no full download when --sample is given."""
    print(f'Streaming {url} ...', file=sys.stderr)
    with httpx.stream('GET', url, follow_redirects=True, timeout=600) as r:
        r.raise_for_status()
        total = 0
        for i, line in enumerate(r.iter_lines()):
            if sample is not None and i >= sample:
                break
            total += len(line)
            if total % (50 * 1024 * 1024) < len(line) + 1:
                print(f'  ~{total / 1e6:.0f} MB read...', file=sys.stderr)
            yield line


def _normalize_code(raw: str | None) -> str | None:
    if not raw:
        return None
    code = NORMALIZE.get(raw, raw)
    return code if code in APP_LANGS else None


def _group_members(obj: dict) -> list[list[tuple[str, str]]]:
    """One member list per sense that has a non-empty translations table:
    the English headword itself, plus every surviving (normalized,
    whitelisted) translation. None if nothing beyond the English word
    itself survives the whitelist for a given sense."""
    word = (obj.get('word') or '').strip().lower()
    if not word:
        return []
    groups = []
    for sense in obj.get('senses') or []:
        translations = sense.get('translations')
        if not translations:
            continue
        members = set()
        for t in translations:
            code = _normalize_code(t.get('code') or t.get('lang_code'))
            w = (t.get('word') or '').strip().lower()
            if code and w:
                members.add((code, w))
        if not members:
            continue  # every translation for this sense got filtered out
        members.add(('en', word))
        groups.append(sorted(members))
    return groups


def build(url: str, out_path: str, sample: int | None):
    if os.path.exists(out_path):
        os.remove(out_path)
    conn = sqlite3.connect(out_path)
    conn.execute('''
        CREATE TABLE members (
            group_id INTEGER NOT NULL,
            lang_code TEXT NOT NULL,
            word TEXT NOT NULL
        )
    ''')

    n_lines = n_groups = n_rows = 0
    next_group_id = 0
    batch: list[tuple[int, str, str]] = []

    def flush():
        nonlocal batch
        if batch:
            conn.executemany(
                'INSERT INTO members (group_id, lang_code, word) '
                'VALUES (?, ?, ?)', batch)
            batch = []

    for line in _iter_lines(url, sample):
        n_lines += 1
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get('lang_code') != 'en':
            continue
        for members in _group_members(obj):
            group_id = next_group_id
            next_group_id += 1
            n_groups += 1
            for code, w in members:
                batch.append((group_id, code, w))
                n_rows += 1
            if len(batch) >= 20000:
                flush()
                conn.commit()

    flush()
    conn.execute('CREATE INDEX idx_lookup ON members(lang_code, word)')
    conn.execute('CREATE INDEX idx_group ON members(group_id)')
    conn.commit()
    conn.close()
    print(f'Parsed {n_lines} lines -> {n_groups} translation groups, '
          f'{n_rows} member rows, written to {out_path}', file=sys.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default=DEFAULT_URL)
    parser.add_argument('--out', default=None)
    parser.add_argument('--sample', type=int, default=None,
                       help='only process the first N JSONL lines (smoke test)')
    args = parser.parse_args()
    out_path = args.out or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'dictionaries', 'cross_translations.sqlite3')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    build(args.url, out_path, args.sample)
