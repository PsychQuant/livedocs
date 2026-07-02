"""TDD for detect.parse_stream — the pure half of trigger detection.

parse_stream turns a `claude -p --output-format stream-json` transcript into
(triggered, tools_fired, final_text, ok). It must recognise a LiveDocs MCP
tool_use (name prefixed `mcp__plugin_livedocs_livedocs__`) as a trigger, ignore
unrelated tools, recover the final answer, and flag `is_error` runs as not-ok.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from detect import parse_stream, LIVEDOCS_PREFIX  # noqa: E402


def _line(obj):
    return json.dumps(obj)


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
    triggered, tools, final, ok = parse_stream(POSITIVE_STREAM)
    assert triggered is True
    assert tools == [LIVEDOCS_PREFIX + "latest_version"]
    assert "1.40.0" in final
    assert ok is True


def test_negative_stream_does_not_trigger_and_ignores_non_livedocs_tool():
    triggered, tools, final, ok = parse_stream(NEGATIVE_STREAM)
    assert triggered is False
    assert tools == []
    assert "hash map" in final
    assert ok is True


def test_multiple_livedocs_tools_all_captured_in_order():
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "a", "name": LIVEDOCS_PREFIX + "resolve_source", "input": {}}]}}),
        _line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "b", "name": LIVEDOCS_PREFIX + "fetch_docs", "input": {}}]}}),
        _line({"type": "result", "result": "done"}),
    ])
    triggered, tools, final, ok = parse_stream(stream)
    assert triggered is True
    assert tools == [LIVEDOCS_PREFIX + "resolve_source", LIVEDOCS_PREFIX + "fetch_docs"]


def test_malformed_lines_are_skipped_not_fatal():
    stream = "not json\n" + _line({"type": "result", "result": "ok"}) + "\n\n{bad json"
    triggered, tools, final, ok = parse_stream(stream)
    assert triggered is False
    assert tools == []
    assert final == "ok"


def test_final_text_falls_back_to_last_assistant_text_without_result_line():
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [{"type": "text", "text": "first"}]}}),
        _line({"type": "assistant", "message": {"content": [{"type": "text", "text": "second"}]}}),
    ])
    _, _, final, _ = parse_stream(stream)
    assert final == "second"


def test_empty_result_string_does_not_clobber_assistant_text():
    # #8: an empty `result` line must not override a real answer.
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [{"type": "text", "text": "real answer 1.2.3"}]}}),
        _line({"type": "result", "result": ""}),
    ])
    _, _, final, _ = parse_stream(stream)
    assert final == "real answer 1.2.3"


def test_is_error_result_marks_run_not_ok():
    # #3: a LiveDocs-triggered run that ends in an error must be flagged not-ok,
    # so the runner does not score its error string as a correct answer.
    stream = "\n".join([
        _line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "t1", "name": LIVEDOCS_PREFIX + "resolve_source", "input": {}}]}}),
        _line({"type": "result", "is_error": True, "result": "API Error: 529 Overloaded"}),
    ])
    triggered, tools, final, ok = parse_stream(stream)
    assert triggered is True          # a tool did fire
    assert ok is False                # but the run errored → not a valid answer
