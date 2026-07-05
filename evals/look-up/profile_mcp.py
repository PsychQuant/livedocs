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
    p = start()
    for n, (label, name, args) in enumerate([
        ("latest_version react (cold)",   "latest_version", {"library": "react", "ecosystem": "npm"}),
        ("latest_version react (warm)",   "latest_version", {"library": "react", "ecosystem": "npm"}),
        ("resolve_source react (cold)",   "resolve_source", {"library": "react", "ecosystem": "npm"}),
        ("resolve_source react (warm)",   "resolve_source", {"library": "react", "ecosystem": "npm"}),
        ("resolve_source fastapi (cold)", "resolve_source", {"library": "fastapi", "ecosystem": "pypi"}),
    ], start=1):
        dt, ok = call(p, n, name, args)
        print(f"{label:38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    p.terminate()

    # Process B: fresh process — the restart penalty (ETag cache is per-process).
    p2 = start()
    dt, ok = call(p2, 1, "resolve_source", {"library": "react", "ecosystem": "npm"})
    print(f"{'resolve_source react (fresh proc)':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    dt, ok = call(p2, 2, "fetch_docs", {"url": "https://react.dev/llms.txt"})
    print(f"{'fetch_docs react llms.txt':38} {dt * 1000:8.0f} ms  {'ok' if ok else 'ERROR'}")
    p2.terminate()


if __name__ == "__main__":
    main()
