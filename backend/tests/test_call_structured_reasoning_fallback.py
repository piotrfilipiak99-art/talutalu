"""_call_structured always asks for the lightest reasoning_effort - "none"
on Gemini, "minimal" on OpenAI - since translation/glossing calls don't
need multi-step reasoning and the default thinking budget was adding real
latency. If a provider rejects the value outright, the call must recover
by retrying without it rather than hard-failing every request forever."""
import json
from types import SimpleNamespace

import ai


def _fake_response(payload: dict):
    return SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(
            content=json.dumps(payload)))],
        usage=SimpleNamespace(prompt_tokens=10, completion_tokens=10),
    )


class _FakeCompletions:
    def __init__(self, behavior):
        self.behavior = behavior  # list of callables, one per call
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        step = self.behavior[len(self.calls) - 1]
        return step()


class _FakeClient:
    def __init__(self, behavior):
        self.chat = SimpleNamespace(completions=_FakeCompletions(behavior))


def test_reasoning_effort_is_sent_and_uses_none_for_gemini(monkeypatch):
    fake = _FakeClient([lambda: _fake_response({"ok": True})])
    monkeypatch.setattr(ai, "_openai", lambda: fake)
    monkeypatch.setattr(ai, "IS_OPENAI", False)

    ai._call_structured("gemini-2.5-flash-lite", "sys", [], "schema",
                        {"type": "object"}, 100)

    assert fake.chat.completions.calls[0]["reasoning_effort"] == "none"


def test_rejected_reasoning_effort_retries_without_it(monkeypatch):
    def reject():
        raise RuntimeError("400 Bad Request: unknown parameter "
                           "'reasoning_effort'")

    fake = _FakeClient([reject, lambda: _fake_response({"ok": True})])
    monkeypatch.setattr(ai, "_openai", lambda: fake)
    monkeypatch.setattr(ai, "IS_OPENAI", False)

    result = ai._call_structured("gemini-2.5-flash-lite", "sys", [],
                                 "schema", {"type": "object"}, 100)

    assert result == {"ok": True}
    assert len(fake.chat.completions.calls) == 2
    assert "reasoning_effort" in fake.chat.completions.calls[0]
    assert "reasoning_effort" not in fake.chat.completions.calls[1]
