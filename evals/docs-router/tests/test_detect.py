"""TDD for detect.parse_stream — the pure half of trigger detection.

parse_stream turns a `claude -p --output-format stream-json` transcript into
(triggered, tools_fired, final_text). It must recognise a LiveDocs MCP tool_use
(name prefixed `mcp__plugin_livedocs_livedocs__`) as a trigger, ignore unrelated
tools (Read/Bash on the user's own code), and recover the final answer text.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from detect import parse_stream, LIVEDOCS_PREFIX  # noqa: E402


def _line(obj):
    return json.dumps(obj)


# A transcript where the model queried LiveDocs then answered.
POSITIVE_STREAM = "\n".join([
    _line({"type": "system", "subtype": "init", "session_id": "x"}),
    _line({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "Let me check the current version."}]}}),
    _line({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "t1",
         "name": LIVEDOCS_PREFIX + "latest_version",
         "input": {"library": "tokio", "ecosystem": "crates"}}]}}),
    _line({"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": "t1", "content": '{"version":"1.40.0"}'}]}}),
    _line({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "The latest version of tokio is 1.40.0."}]}}),
    _line({"type": "result", "subtype": "success", "is_error": False,
           "result": "The latest version of tokio is 1.40.0."}),
])

# A transcript where the model answered a general concept from its own knowledge,
# and even used a NON-LiveDocs tool (Read) — must NOT count as a trigger.
NEGATIVE_STREAM = "\n".join([
    _line({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "r1", "name": "Read",
         "input": {"file_path": "/tmp/user_code.py"}}]}}),
    _line({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "A hash map is a data structure that maps keys to values."}]}}),
    _line({"type": "result", "subtype": "success", "is_error": False,
           "result": "A hash map is a data structure that maps keys to values."}),
])


def test_positive_stream_triggers_and_captures_tool_and_text():
    triggered, tools, final = parse_stream(POSITIVE_STREAM)
    assert triggered is True
    assert tools == [LIVEDOCS_PREFIX + "latest_version"]
    assert "1.40.0" in final


def test_negative_stream_does_not_trigger_and_ignores_non_livedocs_tool():
    triggered, tools, final = parse_stream(NEGATIVE_STREAM)
    assert triggered is False
    assert tools == []
    assert "hash map" in final


def test_multiple_livedocs_tools_all_captured_in_order():
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "a", "name": LIVEDOCS_PREFIX + "resolve_source", "input": {}}]}}),
        _line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "b", "name": LIVEDOCS_PREFIX + "fetch_docs", "input": {}}]}}),
        _line({"type": "result", "result": "done"}),
    ])
    triggered, tools, final = parse_stream(stream)
    assert triggered is True
    assert tools == [LIVEDOCS_PREFIX + "resolve_source", LIVEDOCS_PREFIX + "fetch_docs"]


def test_malformed_lines_are_skipped_not_fatal():
    stream = "not json\n" + _line({"type": "result", "result": "ok"}) + "\n\n{bad json"
    triggered, tools, final = parse_stream(stream)
    assert triggered is False
    assert tools == []
    assert final == "ok"


def test_final_text_falls_back_to_last_assistant_text_without_result_line():
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [{"type": "text", "text": "first"}]}}),
        _line({"type": "assistant", "message": {"content": [{"type": "text", "text": "second"}]}}),
    ])
    _, _, final = parse_stream(stream)
    assert final == "second"
