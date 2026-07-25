#!/usr/bin/env python3
"""One-time, manual, offline build of a target->base dictionary SQLite from
a kaikki.org/Wiktextract per-language JSONL extract. NOT part of the FastAPI
runtime - run this locally, then upload the resulting .sqlite3 as a GitHub
Release asset (see backend/dictionary.py for the download side).

Usage:
    python build_dictionary.py                    # full Polish build
    python build_dictionary.py --sample 5000       # first 5000 lines only, for smoke-testing
    python build_dictionary.py --url URL --lang pl --out pl-en.sqlite3

Source: kaikki.org publishes English-Wiktionary-derived entries per
headword language. Glosses are always written in English, so the resulting
dictionary only ever helps lookups where base_lang == 'en'.

License: Wiktionary content, CC BY-SA. kaikki.org's requested attribution
(reproduced in the app's profile screen):
    Tatu Ylonen: Wiktextract: Wiktionary as Machine-Readable Structured
    Data, Proceedings of the 13th Conference on Language Resources and
    Evaluation (LREC), pp. 1317-1325
"""
import argparse
import json
import os
import sqlite3
import sys

import httpx

DEFAULT_URL = 'https://kaikki.org/dictionary/Polish/kaikki.org-dictionary-Polish.jsonl'
DEFAULT_LANG = 'pl'
DEFAULT_BASE = 'en'

# Etymology template names that name simple word-part morphemes. Only these
# are used for root/rootMeaning - anything else (or unresolvable parts) is
# left as None. Never parse free-text etymology prose: too fragile, risks
# fabricating ungrounded "facts" (see project_root_field_grounding policy).
_MORPHEME_TEMPLATES = {'affix', 'compound', 'prefix', 'suffix'}


def _iter_lines(url: str, sample: int | None):
    """Yields raw JSON lines, streaming straight off the HTTP response - no
    temp file, no full download when --sample is given (the connection is
    closed as soon as enough lines have been read)."""
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


def _clean_gloss(glosses: list[str]) -> str | None:
    """Wiktextract's 'glosses' is a sense hierarchy (broad topic labels
    first, most specific definition last) - the last item is what we want."""
    if not glosses:
        return None
    text = glosses[-1].strip()
    return text or None


def _parse_entry(obj: dict) -> dict | None:
    word = (obj.get('word') or '').strip().lower()
    pos = obj.get('pos')
    if not word or not pos:
        return None
    glosses = []
    for sense in obj.get('senses') or []:
        # Redirect-style senses ("inflection of X", "alternative form of
        # X", ...) aren't real definitions - Wiktextract marks these with
        # a dedicated 'form_of'/'alt_of' key whenever they apply, which is
        # far more robust to key on than the free-form 'tags' list.
        if sense.get('form_of') or sense.get('alt_of'):
            continue
        gloss = _clean_gloss(sense.get('glosses') or [])
        if gloss:
            glosses.append(gloss)
    if not glosses:
        return None  # lemma-only entry with nothing but redirect pointers

    root_parts = None
    for tmpl in obj.get('etymology_templates') or []:
        if tmpl.get('name') not in _MORPHEME_TEMPLATES:
            continue
        # arg '1' is conventionally the language code (e.g. {{affix|pl|...}})
        # - the word parts start at '2'.
        args = tmpl.get('args') or {}
        parts = [v.strip().lower() for k, v in args.items()
                if k.isdigit() and int(k) >= 2 and isinstance(v, str)
                and v.strip()]
        parts = [p for p in parts if p and not p.isdigit()]
        if len(parts) >= 2:
            root_parts = parts
            break  # first clean template wins

    return {'lemma': word, 'pos': pos, 'glosses': glosses,
           'root_parts': root_parts}


def build(url: str, lang: str, base: str, out_path: str, sample: int | None):
    records = []
    n_lines = 0
    for line in _iter_lines(url, sample):
        n_lines += 1
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get('lang_code') != lang:
            continue
        rec = _parse_entry(obj)
        if rec:
            records.append(rec)
    print(f'Parsed {len(records)} lemma entries from {n_lines} lines.',
          file=sys.stderr)

    # Index for resolving etymology parts against the dictionary's own
    # entries (RAG-style: only use meanings we already trust, never invent
    # one). Keyed by lemma only - first matching entry's first gloss wins.
    by_lemma: dict[str, str] = {}
    for rec in records:
        by_lemma.setdefault(rec['lemma'], rec['glosses'][0])

    if os.path.exists(out_path):
        os.remove(out_path)
    conn = sqlite3.connect(out_path)
    conn.execute('''
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            lemma TEXT NOT NULL,
            pos TEXT NOT NULL,
            sense_rank INTEGER NOT NULL,
            gloss TEXT NOT NULL,
            root TEXT,
            root_meaning TEXT
        )
    ''')
    n_rows = 0
    n_rooted = 0
    for rec in records:
        root = root_meaning = None
        if rec['root_parts']:
            part_glosses = [by_lemma.get(p) for p in rec['root_parts']]
            if all(part_glosses):
                root = '+'.join(rec['root_parts'])
                root_meaning = '+'.join(part_glosses)
                n_rooted += 1
        for rank, gloss in enumerate(rec['glosses']):
            conn.execute(
                'INSERT INTO entries (lemma, pos, sense_rank, gloss, root, '
                'root_meaning) VALUES (?, ?, ?, ?, ?, ?)',
                (rec['lemma'], rec['pos'], rank, gloss, root, root_meaning))
            n_rows += 1
    conn.execute('CREATE INDEX idx_lemma_pos ON entries(lemma, pos)')
    conn.commit()
    conn.close()
    print(f'Wrote {n_rows} rows ({n_rooted} entries with a resolved root) '
          f'to {out_path}', file=sys.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default=DEFAULT_URL)
    parser.add_argument('--lang', default=DEFAULT_LANG,
                       help='lang_code to keep (matches UDPipe lemma language)')
    parser.add_argument('--base', default=DEFAULT_BASE,
                       help='base language the glosses are written in')
    parser.add_argument('--out', default=None)
    parser.add_argument('--sample', type=int, default=None,
                       help='only process the first N JSONL lines (smoke test)')
    args = parser.parse_args()
    out_path = args.out or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'dictionaries', f'{args.lang}-{args.base}.sqlite3')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    build(args.url, args.lang, args.base, out_path, args.sample)
