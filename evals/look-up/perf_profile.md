# LiveDocs performance profile — dated capture (#56)

> **Captured 2026-07-06** on one machine (Apple Silicon macOS, home network), small n —
> **directional, not a benchmark**. The same measured-never-asserted rule as the
> vs-context7 snapshot applies: don't quote these numbers as timeless facts; re-run
> the harness for today's. Reproduce: `python3 evals/look-up/profile_mcp.py`
> (+ the static greps and the delegation command inline below).

The question (#56): within the architecture boundary — *local tool, direct to primary
source, **no central content cache*** (`docs/positioning.md` anti-positioning) — where
is the acceleration headroom, and does subagent/cheap-model delegation help?

## ① Engine: tool-call latency (MCP stdio, signed binary, no agent loop)

| call | cold | warm (same process) |
|---|---:|---:|
| `latest_version react npm` | 344 ms | **32 ms** |
| `resolve_source react npm` | 367–385 ms | 271 ms |
| `resolve_source fastapi pypi` | **1159 ms** | — |
| `fetch_docs react.dev/llms.txt` | 205 ms | — |

Two structural facts behind these numbers (static, from source — stable until the code
changes):

- **All probing is sequential.** `grep -rn 'withTaskGroup\|async let' Sources/` → 0 hits;
  every candidate chain is `for` + `await` (`DiscoveryEngine.swift:89,142,173-188,402`).
  fastapi at ~3× react is the multi-candidate penalty paid linearly.
- **The ETag cache is per-process, in-memory only** (`ETagCache.swift` docstring:
  *"empty on restart. Persisting to disk is a possible follow-up."*). The 10× warm win
  (344 → 32 ms) dies with every MCP server restart.

## ② `look-up` skill: main-loop round-trips

From the skill's routing table: docs/config questions = `resolve_source` → **then**
`fetch_docs` (2 sequential main-loop round-trips); version = 1 (`latest_version`);
version-reconciliation adds `introspect` (up to 3). Each round-trip costs a **main-model
turn** (seconds of generation/thinking) — an order of magnitude more than the 0.3–1.2 s
the tool itself takes. **End-to-end latency is dominated by the number of turns, not by
fetch time.**

## ③ The subagent / cheap-model (haiku) delegation hypothesis — measured

```
cd <clean dir> && /usr/bin/time -p claude -p "reply with exactly: ok" \
    --model haiku --strict-mcp-config --dangerously-skip-permissions
# real 9.00   (user 2.39, sys 2.03) — clean config; nested-in-session is worse
```

Headless haiku spawn ≈ **9 s wall** vs the 0.3–1.2 s fetch it would replace: a net
**8–25× loss for single-shot lookups**. The hypothesis is **refuted for the single-query
case**; it survives only where one spawn amortizes over a *batch* of lookups (≳10), or
where the goal is context-isolation / token cost rather than latency. (Dev-flow
delegation — cheap-model tiering of verify lenses — is prior art in this repo and is a
*cost* win, orthogonal to query latency.)

## Where the headroom actually is (decomposition)

The instinct "hand work to a cheap worker" is right — but the cheapest worker is the
**MCP server itself**, not a subagent:

1. **Composite one-call lookup** — resolve + fetch-top-result server-side in one tool
   call: removes an entire main-model turn (~seconds) at zero spawn cost. Largest
   measured lever.
2. **Parallelize the probe chains** (`withTaskGroup` over candidates): multi-candidate
   resolves approach the slowest single probe instead of the sum (target: fastapi
   1159 → ~400 ms class).
3. **Disk-persist the ETag cache** (keep the LRU/byte bounds; local-only, squarely
   inside the anti-positioning boundary): the 10× warm state survives restarts.

Each is filed as a child issue of #56 with these numbers as the justification; see the
task list in #56's body.

## Caveats (read before quoting)

- n is tiny; one machine, one network, one day. Directional only.
- Timings are engine-side (stdio): they exclude the agent-loop overhead that dominates
  ② — which is precisely the point of splitting ① from ②.
- The 9 s delegation number is `claude -p` with a clean config — the in-session Agent
  tool differs in mechanism but not in order of magnitude; nested runs inherit the
  parent's MCP config and are slower (see the cost note in `README.md`).
- "加速" as *perceived* speed also includes main-model thinking time between turns,
  which no LiveDocs change can touch — conceded. The actionable product is
  turns × in-call latency.
