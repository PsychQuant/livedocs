"""Trigger detection: did a prompt make the look-up skill query LiveDocs?

Two halves:
  - parse_stream(text)   PURE  — turn a `claude -p --output-format stream-json`
                                 transcript into (triggered, tools_fired, final_text, ok).
  - run_prompt(prompt)   IMPURE — shell out to `claude -p` and feed its stream to
                                 parse_stream.

"Triggered" means at least one MCP tool whose name starts with
`mcp__plugin_livedocs_livedocs__` fired — the real installed-plugin signal.
Non-LiveDocs tools (Read/Bash on the user's own code) are ignored on purpose.

`ok` is False when the run itself failed (the CLI reported `is_error`, exited
non-zero, or timed out). A failed run is NOT evidence of correct behavior — the
runner excludes it from the rate denominators rather than scoring it as a clean
non-trigger (which would let a broken/out-of-credits environment spuriously pass
every negative case).
"""
from __future__ import annotations

import json
import subprocess
from typing import List, Tuple

# The MCP tool namespace of the installed livedocs plugin. A tool_use with this
# name prefix is a LiveDocs query — the thing this eval measures.
LIVEDOCS_PREFIX = "mcp__plugin_livedocs_livedocs__"


def parse_stream(text: str) -> Tuple[bool, List[str], str, bool]:
    """Parse newline-delimited stream-json into (triggered, tools_fired, final_text, ok).

    - tools_fired: LiveDocs tool names in call order.
    - final_text: the `result` line if non-empty, else the last assistant text
      block (an empty `result` no longer clobbers a real answer).
    - ok: False if any `result` line has `is_error: true` — an errored run that
      happened to fire a tool must not be scored as a correct answer.
    - Malformed / non-JSON lines are skipped, never fatal.
    """
    tools_fired: List[str] = []
    last_assistant_text = ""
    result_text = None
    is_error = False

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(obj, dict):
            continue

        otype = obj.get("type")
        if otype == "assistant":
            content = (obj.get("message") or {}).get("content") or []
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    name = block.get("name", "")
                    if isinstance(name, str) and name.startswith(LIVEDOCS_PREFIX):
                        tools_fired.append(name)
                elif block.get("type") == "text":
                    txt = block.get("text")
                    if isinstance(txt, str) and txt.strip():
                        last_assistant_text = txt
        elif otype == "result":
            res = obj.get("result")
            if isinstance(res, str):
                result_text = res
            if obj.get("is_error") is True:
                is_error = True

    # An empty result string must not override a real assistant answer (#8).
    final_text = result_text if result_text else last_assistant_text
    triggered = len(tools_fired) > 0
    ok = not is_error
    return triggered, tools_fired, final_text, ok


def run_prompt(prompt: str, cwd: str | None = None, timeout: int = 180,
               extra_args: List[str] | None = None) -> Tuple[bool, List[str], str, bool]:
    """Run one prompt headlessly and return (triggered, tools_fired, final_text, ok).

    The prompt is fed via **stdin** (not an argv slot) so a prompt beginning with
    `-` can never be parsed as a CLI flag. `ok` is False on a non-zero exit, a
    timeout, or an `is_error` stream — the runner treats those as failed runs.
    livedocs MCP tools are read-only, so the eval runs with
    `--dangerously-skip-permissions` to avoid an interactive prompt hanging a
    non-interactive run.
    """
    cmd = [
        "claude", "-p",
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]
    if extra_args:
        cmd += extra_args
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, input=prompt, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, [], "__timeout__", False
    except FileNotFoundError:
        raise RuntimeError("`claude` CLI not found on PATH — install Claude Code to run the live eval")

    triggered, tools, final, parse_ok = parse_stream(proc.stdout)
    ok = parse_ok and proc.returncode == 0
    return triggered, tools, final, ok
