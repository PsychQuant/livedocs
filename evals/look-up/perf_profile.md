# LiveDocs performance profile — dated capture (#56)

> **Captured 2026-07-06** on one machine (Apple Silicon macOS, home network), small n —
> **directional, not a benchmark**. The same measured-never-asserted rule as the
> vs-context7 snapshot applies: don't quote these numbers as timeless facts; re-run
> the harness for today's. Reproduce: `python3 evals/look-up/profile_mcp.py`
> (+ the static greps and the delegation command inline below).
>
> **Capture note**: the first capture that day had an ordering bias — `resolve_source
> react` ran after `latest_version` calls had already ETag-/connection-warmed the
> registry leg, understating its cold cost (367 ms vs the unbiased 649 ms). The
> harness was fixed (each library's resolve runs first in its process) and the table
> below is the corrected capture. Kept here as a worked example of why single runs
> mislead.

The question (#56): within the architecture boundary — *local tool, direct to primary
source, **no central content cache*** (`docs/positioning.md` anti-positioning) — where
is the acceleration headroom, and does subagent/cheap-model delegation help?

## What is stable vs what is noise

Two kinds of claims below, deliberately separated:

- **Structural facts** (from source code — stable until the code changes): probing is
  sequential; the ETag cache is per-process. These are the load-bearing claims.
- **Timings** (network-dominated — high run-to-run variance): observed spreads across
  same-day runs were wide (`fetch_docs` 205→611 ms; `latest_version` fresh-process
  60→344 ms). Treat every number as an order-of-magnitude cue, not a value.

## ① Engine: tool-call latency (MCP stdio, signed binary, no agent loop)

Corrected capture (each library's resolve is the first call its hosts see):

| call | this capture | observed same-day spread |
|---|---:|---:|
| `resolve_source react npm` (true cold) | 649 ms | 353–649 ms |
| `resolve_source react npm` (warm, same process) | 259 ms | 259–321 ms |
| `resolve_source fastapi pypi` (true cold) | 1146 ms | 1055–1159 ms |
| `latest_version react npm` (fresh process) | 60 ms | 60–344 ms |
| `latest_version react npm` (warm) | 23–27 ms | — |
| `fetch_docs react.dev/llms.txt` | 611 ms | 205–611 ms |

Structural facts behind the numbers:

- **All probing is sequential.** `grep -rn 'withTaskGroup\|async let' Sources/` → 0 hits;
  every candidate chain is `for` + `await` (`DiscoveryEngine.swift:89,142,173-188,402`).
- **fastapi cold ≈ 1.8× react cold** (1146 vs 649 ms) on the unbiased capture — *consistent
  with* summed sequential probes (fastapi's chain probes more candidates), but this
  harness times whole calls only: it **cannot separate** per-probe count from
  slower-host latency. #57's diagnosis must instrument per-probe timing before
  projecting a parallelization gain; the earlier "1159 → ~400 ms class" projection is
  conditional on the cost actually being summed probes.
- **The ETag cache is per-process, in-memory only** (`ETagCache.swift` docstring:
  *"empty on restart. Persisting to disk is a possible follow-up."*). Warm calls are
  consistently faster; the observed warm win ranged **~2× to ~10×** across runs, and
  the win is **not attributable to the ETag cache alone** — connection keep-alive /
  DNS / TLS reuse are confounded in it and also die on restart. Implication for #58:
  disk-persisting the ETag cache recovers only the revalidation part of the warm win
  on a fresh process; the connection-setup part is not recoverable by any cache.

## ② `look-up` skill: main-loop round-trips

From the skill's routing table: docs/config questions = `resolve_source` → **then**
`fetch_docs` (2 sequential main-loop round-trips); version = 1 (`latest_version`);
version-reconciliation adds `introspect` (up to 3).

**Measured here**: only the tool-side of each round-trip (0.3–1.2 s above).
**Asserted, not measured** (this harness is engine-side by design): each round-trip
also costs a main-model turn — generation/thinking time that in ordinary agent use
runs seconds per turn, i.e. plausibly larger than the tool time it wraps. That is a
claim from general agent-loop behavior, stated as such; measuring it would need an
agent-side (not engine-side) harness.

## ③ The subagent / cheap-model (haiku) delegation hypothesis — measured

```
cd <clean dir> && /usr/bin/time -p claude -p "reply with exactly: ok" \
    --model haiku --strict-mcp-config --dangerously-skip-permissions
# real 9.00   (user 2.39, sys 2.03) — clean config; nested-in-session is worse
```

Headless haiku spawn ≈ **9 s wall** vs the 0.3–1.2 s fetch it would replace: a net
**~7–30× loss for single-shot lookups** (9/1.2 ≈ 7.5; 9/0.3 = 30). The hypothesis is
**refuted for the single-query case**; it survives only where one spawn amortizes over
a *batch* of lookups (≳10), or where the goal is context-isolation / token cost rather
than latency. Caveats stated plainly: the 9 s is a `claude -p` **proxy** for the
in-session Agent tool — mechanism differs, and "same order of magnitude" is an
**assertion**, not a measurement (the supporting direction: nested in-session runs
inherit the parent's MCP config and are *slower*, per the cost note in `README.md`).
Dev-flow delegation — cheap-model tiering of verify lenses — is prior art in this repo
and is a *cost* win, orthogonal to query latency.

## Where the headroom actually is (decomposition)

The instinct "hand work to a cheap worker" is right — but the cheapest worker is the
**MCP server itself**, not a subagent:

1. **Composite one-call lookup** — resolve + fetch-top-result server-side in one tool
   call: removes an entire main-model turn at zero spawn cost. Largest **expected**
   lever — expected, not measured, because its magnitude is the per-turn cost that
   this engine-side harness deliberately does not measure (see ②).
2. **Parallelize the probe chains** (`withTaskGroup` over candidates): multi-candidate
   resolves approach the slowest single probe instead of the sum — *if* #57's
   per-probe instrumentation confirms the cost is summed probes (see ①).
3. **Disk-persist the ETag cache** (keep the LRU/byte bounds; local-only, squarely
   inside the anti-positioning boundary): recovers the revalidation share of the warm
   win across restarts (not the connection-setup share — stated in ①).

Each is filed as a child issue of #56 with these numbers as the justification; see the
task list in #56's body.

## Caveats (read before quoting)

- n is tiny; one machine, one network, one day; same-day spreads above show the noise
  floor. Directional only.
- Timings are engine-side (stdio): they exclude the agent-loop overhead discussed in
  ② — which is precisely the point of splitting ① from ②, and why ②'s turn-cost
  claim is labeled asserted.
- The 9 s delegation number is `claude -p` with a clean config; the in-session Agent
  tool was not separately timed (assertion of same order of magnitude, direction
  supported by the nested-run cost note in `README.md`).
- "加速" as *perceived* speed also includes main-model thinking time between turns,
  which no LiveDocs change can touch — conceded. The actionable product is
  turns × in-call latency.
