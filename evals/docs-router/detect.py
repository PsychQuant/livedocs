"""Trigger detection: did a prompt make the docs-router skill query LiveDocs?

Two halves:
  - parse_stream(text)   PURE  — turn a `claude -p --output-format stream-json`
                                 transcript into (triggered, tools_fired, final_text).
  - run_prompt(prompt)   IMPURE — shell out to `claude -p` and feed its stream to
                                 parse_stream.

"Triggered" means at least one MCP tool whose name starts with
`mcp__plugin_livedocs_livedocs__` fired — the real installed-plugin signal.
Non-LiveDocs tools (Read/Bash on the user's own code) are ignored on purpose.
"""
from __future__ import annotations

import json
import subprocess
from typing import List, Tuple

# The MCP tool namespace of the installed livedocs plugin. A tool_use with this
# name prefix is a LiveDocs query — the thing this eval measures.
LIVEDOCS_PREFIX = "mcp__plugin_livedocs_livedocs__"


def parse_stream(text: str) -> Tuple[bool, List[str], str]:
    """Parse newline-delimited stream-json into (triggered, tools_fired, final_text).

    - tools_fired: LiveDocs tool names in call order (dedup-free; a repeat is a repeat).
    - final_text: the `result` line if present, else the last assistant text block.
    - Malformed / non-JSON lines are skipped, never fatal (the CLI can interleave
      log noise).
    """
    tools_fired: List[str] = []
    last_assistant_text = ""
    result_text = None

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

    final_text = result_text if result_text is not None else last_assistant_text
    triggered = len(tools_fired) > 0
    return triggered, tools_fired, final_text


def run_prompt(prompt: str, cwd: str | None = None, timeout: int = 180,
               extra_args: List[str] | None = None) -> Tuple[bool, List[str], str]:
    """Run one prompt headlessly and return (triggered, tools_fired, final_text).

    Uses `claude -p <prompt> --output-format stream-json --verbose`. The livedocs
    MCP tools are read-only, so the eval runs with `--dangerously-skip-permissions`
    to avoid an interactive permission prompt hanging a non-interactive run
    (override via extra_args if your setup allowlists tools differently).
    """
    cmd = [
        "claude", "-p", prompt,
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]
    if extra_args:
        cmd += extra_args
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, [], "__timeout__"
    except FileNotFoundError:
        raise RuntimeError("`claude` CLI not found on PATH — install Claude Code to run the live eval")
    return parse_stream(proc.stdout)
