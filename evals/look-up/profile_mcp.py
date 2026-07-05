#!/usr/bin/env python3
"""Time LiveDocs MCP tool calls over stdio (#56 performance profile harness).

Speaks the MCP stdio transport (newline-delimited JSON-RPC) directly to the
installed binary, so the timings are ENGINE-side — no agent loop, no framework
overhead. Two processes: A measures cold→warm within one server lifetime (the
in-memory ETag cache), B measures a fresh-process cold start.

Usage:
    python3 evals/look-up/profile_mcp.py [/path/to/CheLiveDocsMCP]

Honesty: small n, one machine, one network — DIRECTIONAL, not a benchmark.
Numbers land in perf_profile.md as a dated capture (measured, never asserted).
"""
import json
import subprocess
import sys
import time

BIN = sys.argv[1] if len(sys.argv) > 1 else "/Users/che/bin/CheLiveDocsMCP"


def rpc(proc, msg):
    proc.stdin.write((json.dumps(msg) + "\n").encode())
    proc.stdin.flush()
    if "id" not in msg:
        return None, 0.0
    t0 = time.monotonic()
    while True:
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError("server closed the pipe")
        try:
            resp = json.loads(line)
        except json.JSONDecodeError:
            continue
        if resp.get("id") == msg["id"]:
            return resp, time.monotonic() - t0


def start():
    p = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL)
    rpc(p, {"jsonrpc": "2.0", "id": 0, "method": "initialize",
            "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                       "clientInfo": {"name": "perf", "version": "0"}}})
    rpc(p, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    return p


def call(p, i, name, args):
    resp, dt = rpc(p, {"jsonrpc": "2.0", "id": i, "method": "tools/call",
                       "params": {"name": name, "arguments": args}})
    return dt, "error" not in resp


def main():
    print(f"binary: {BIN}\n")
    # Process A: cold→warm within one server lifetime (in-memory ETag effect).
    # ORDERING (#56 verify): each library's resolve_source runs FIRST in the process,
    # before any other call touches its hosts — otherwise a prior latest_version call
    # ETag-/connection-warms the registry leg and biases the "cold" resolve (the
    # ordering bias the round-1 review caught in the original capture).
    p = start()
    for n, (label, name, args) in enumerate([
        ("resolve_source react (cold)",   "resolve_source", {"library": "react", "ecosystem": "npm"}),
        ("resolve_source react (warm)",   "resolve_source", {"library": "react", "ecosystem": "npm"}),
        ("latest_version react (cold*)",  "latest_version", {"library": "react", "ecosystem": "npm"}),
        ("latest_version react (warm)",   "latest_version", {"library": "react", "ecosystem": "npm"}),
        ("resolve_source fastapi (cold)", "resolve_source", {"library": "fastapi", "ecosystem": "pypi"}),
    ], start=1):
        dt, ok = call(p, n, name, args)
        print(f"{label:38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    print("  (* latest_version react runs after resolve_source warmed the registry —")
    print("     within-process 'cold' only for the tool, not the connection/ETag)")
    p.terminate()

    # Process B: fresh processes — the restart penalty (ETag cache is per-process).
    # latest_version gets its own fresh process so ITS cold number carries no
    # within-process warming from A.
    p2 = start()
    dt, ok = call(p2, 1, "latest_version", {"library": "react", "ecosystem": "npm"})
    print(f"{'latest_version react (fresh proc)':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    dt, ok = call(p2, 2, "latest_version", {"library": "react", "ecosystem": "npm"})
    print(f"{'latest_version react (warm)':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    dt, ok = call(p2, 3, "resolve_source", {"library": "react", "ecosystem": "npm"})
    print(f"{'resolve_source react (proc-warm)':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    dt, ok = call(p2, 4, "fetch_docs", {"url": "https://react.dev/llms.txt"})
    print(f"{'fetch_docs react llms.txt':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    p2.terminate()


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError:
        print(f"binary not found: {BIN}\n"
              f"pass the CheLiveDocsMCP path as argv[1], e.g.\n"
              f"  python3 evals/look-up/profile_mcp.py ~/bin/CheLiveDocsMCP",
              file=sys.stderr)
        raise SystemExit(1)
