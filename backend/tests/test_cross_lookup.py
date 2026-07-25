import sqlite3

import pytest

import dictionary


@pytest.fixture
def fixture_cross_db(tmp_path, monkeypatch):
    monkeypatch.setattr(dictionary, "DICT_DIR", str(tmp_path))
    dictionary._cross_conn = None

    path = tmp_path / dictionary._CROSS_ASSET
    conn = sqlite3.connect(path)
    conn.execute("""
        CREATE TABLE members (
            group_id INTEGER NOT NULL, lang_code TEXT NOT NULL,
            word TEXT NOT NULL
        )
    """)
    rows = [
        # "guy, fellow" sense of "cat" - one unambiguous answer per language
        (1, "en", "cat"), (1, "da", "fyr"), (1, "es", "tio"),
        # a genuinely ambiguous sense: two Finnish words for the same group
        (1, "fi", "kundi"), (1, "fi", "heppu"),
        # a completely unrelated sense of "cat" (the animal) - must not
        # leak into the "guy" group's answers
        (2, "en", "cat"), (2, "pl", "kot"),
    ]
    conn.executemany(
        "INSERT INTO members (group_id, lang_code, word) VALUES (?, ?, ?)",
        rows)
    conn.execute("CREATE INDEX idx_lookup ON members(lang_code, word)")
    conn.execute("CREATE INDEX idx_group ON members(group_id)")
    conn.commit()
    conn.close()
    yield
    dictionary._cross_conn = None


def test_unambiguous_match(fixture_cross_db):
    assert dictionary.cross_lookup("cat", "en", "da") == "fyr"
    assert dictionary.cross_lookup("cat", "en", "es") == "tio"


def test_ambiguous_match_returns_list(fixture_cross_db):
    result = dictionary.cross_lookup("cat", "en", "fi")
    assert isinstance(result, list)
    assert sorted(result) == ["heppu", "kundi"]


def test_no_match_returns_none(fixture_cross_db):
    assert dictionary.cross_lookup("cat", "en", "de") is None
    assert dictionary.cross_lookup("nonexistent", "en", "es") is None


def test_separate_groups_both_contribute(fixture_cross_db):
    # "cat" appears in two unrelated groups (guy/animal); a language present
    # in only one of them still resolves via that group alone.
    assert dictionary.cross_lookup("cat", "en", "pl") == "kot"
