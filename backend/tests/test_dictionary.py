import sqlite3

import pytest

import dictionary


@pytest.fixture
def fixture_db(tmp_path, monkeypatch):
    monkeypatch.setattr(dictionary, "DICT_DIR", str(tmp_path))
    dictionary.DICT_PAIRS.add(("pl", "en"))
    dictionary._conns.clear()

    path = tmp_path / "pl-en.sqlite3"
    conn = sqlite3.connect(path)
    conn.execute("""
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY, lemma TEXT NOT NULL, pos TEXT NOT NULL,
            sense_rank INTEGER NOT NULL, gloss TEXT NOT NULL,
            root TEXT, root_meaning TEXT
        )
    """)
    rows = [
        # single-sense noun, no etymology
        ("kot", "noun", 0, "cat", None, None),
        # multi-sense homonym: "pole" as noun (field) vs noun (pole/rod)
        ("pole", "noun", 0, "field", None, None),
        ("pole", "noun", 1, "pole, rod", None, None),
        # a verb (translation must never be auto-filled for verbs)
        ("isc", "verb", 0, "to go", None, None),
        # single-sense noun WITH a resolved root
        ("naprawa", "noun", 0, "repair", "na+prawic", "onto+to fix"),
    ]
    conn.executemany(
        "INSERT INTO entries (lemma, pos, sense_rank, gloss, root, "
        "root_meaning) VALUES (?, ?, ?, ?, ?, ?)", rows)
    conn.execute("CREATE INDEX idx_lemma_pos ON entries(lemma, pos)")
    conn.commit()
    conn.close()
    yield
    dictionary._conns.clear()


def test_unsupported_pair_returns_none():
    assert dictionary.lookup("kot", "NOUN", "pl", "es") is None


def test_single_sense_noun(fixture_db):
    entry = dictionary.lookup("kot", "NOUN", "pl", "en")
    assert entry == {"senses": ["cat"], "root": None, "rootMeaning": None}


def test_multi_sense_homonym_returns_both(fixture_db):
    entry = dictionary.lookup("pole", "NOUN", "pl", "en")
    assert entry["senses"] == ["field", "pole, rod"]


def test_verb_lookup_still_returns_gloss(fixture_db):
    # dictionary.py itself doesn't know about the translation-safety rule
    # (that's annotate.py's job) - it should just return what's there.
    entry = dictionary.lookup("isc", "VERB", "pl", "en")
    assert entry["senses"] == ["to go"]


def test_missing_lemma_returns_none(fixture_db):
    assert dictionary.lookup("nieistniejace", "NOUN", "pl", "en") is None


def test_root_resolved_when_present(fixture_db):
    entry = dictionary.lookup("naprawa", "NOUN", "pl", "en")
    assert entry["root"] == "na+prawic"
    assert entry["rootMeaning"] == "onto+to fix"


def test_pos_mismatch_falls_back_unfiltered(fixture_db):
    # "kot" only has a "noun" row; asking with UD tag VERB (mapped to
    # wiktextract's {'verb'}) finds nothing on the filtered pass, so
    # lookup() must retry unfiltered rather than returning None outright.
    entry = dictionary.lookup("kot", "VERB", "pl", "en")
    assert entry is not None
    assert entry["senses"] == ["cat"]
