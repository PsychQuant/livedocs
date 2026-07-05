# LiveDocs — Positioning

> External-messaging source of truth. Companion to
> [primary-source-spectrum.md](wiki/Primary-Source-Spectrum.md) (the product boundary).

## One-liner

> Live docs, matched to the version you have installed. Straight from the source, on
> your machine. No stale index, no API key.

## The wedge (what we lead with)

The pain: always-latest, straight from the source, with no periodically-recrawled index
sitting in between.

Why that holds and is hard to copy: LiveDocs runs locally and goes direct to the source.
That is also why it is private and needs no API key. context7 is a centralized service;
it can't become local, private, and keyless without giving up its model.

Lead with the outcome (latest, private, keyless). "Decentralized" is the mechanism behind
that outcome, not the headline.

## The sharpest angle: "the docs your code actually runs on"

Beyond "latest published," LiveDocs reconciles against the version you have installed
(version reconciliation + `introspect`). It answers for the version you actually run, not
whatever is newest. That kills the version-skew bug: the docs say to use X, but the copy
on your machine doesn't have it. Even latest-only tools miss this. Make it a lead, not a
footnote.

## Three differentiators (all follow from local + direct)

1. Latest. Live from the registry, `llms.txt`, repo, or introspection; never a recrawled
   snapshot. Proof (measured 2026-07-02 by the
   [vs-context7 harness](../evals/look-up/README.md#vs-context7-comparison-issue-27)):
   context7's best version-tagged fastapi entry was `0.128.0` while PyPI was at `0.139.0`,
   about ten releases behind — and its *top-ranked* match carried no version at all. Numbers
   rot (this line once said `0.138.2`); the harness is the living source — re-run
   `evals/look-up/compare_context7.py` for today's.
2. Private and free, by construction. Your query goes straight to the authoritative source
   (npm, PyPI, the docs host) with no third-party index in between to see, log, meter, or
   breach it — and version reconciliation reads your locally-installed copy offline. There is
   no LiveDocs vendor at all. No account, no API key, no seat, no per-token fee for private
   repos. Matching that vendor-free posture on context7 means self-hosting, a paid tier.
   (context7 is SOC-2-certified and *offers* self-host — the edge is structural absence, not
   that context7 is unsafe; see the head-to-head.)
3. Raw and installed. Returns verbatim primary text, and can read the version you actually
   have. context7 returns ranked, model-summarized snippets, often weeks old.

## Head-to-head vs context7

| Dimension | LiveDocs | context7 |
|---|---|---|
| Freshness | live, direct-to-source, ETag-revalidated | periodically recrawled, so it lags |
| Fidelity | raw verbatim reachable | ranked, model-summarized snippets |
| Your environment | matched to the installed version | version-agnostic snapshot |
| Architecture | local tool, no vendor backend | hosted SaaS by default (self-host is a paid tier) |
| Privacy | no third-party index sees your query (direct to source) | default routes through their cloud (local processing + SOC-2 claimed) |
| Cost | free, unmetered; private repos included | metered free tier (public only) + paid Pro / Enterprise |
| Breadth | ~any public lib via generic discovery + adapters | large pre-indexed corpus |

The Freshness row is measured, not asserted: the
[vs-context7 harness](../evals/look-up/README.md#vs-context7-comparison-issue-27)
(dated capture + per-library data, honesty caveats inline) is the living source of the
head-to-head numbers — cite it rather than copying figures into prose that will rot.

The Architecture / Privacy / Cost rows are cited from context7's own pages, with the
concessions inline (measured-not-asserted applies to every competitive axis, not just
freshness). Both are **structural** claims, not measured metrics — so the honesty mechanism
is dated citation + concession, not a drift-guarded number:

- **Vendor / privacy.** context7's default is a managed cloud service ("Built by Upstash"; a
  dedicated hosted database per organization). It *offers* self-hosted / on-premise, claims
  local query processing, and is SOC-2 Type II certified. LiveDocs has no vendor server at all
  — nothing to deploy, trust, or breach. The edge is *structural absence*, not that context7 is
  insecure; note that vendor-free operation on context7 is itself the paid self-host tier.
- **Cost** (dated capture, context7 pricing 2026-07-05): Free = 1,000 calls/mo, public repos
  only; Pro = $10/seat/mo, with private-repo parsing billed at $25 / 1M tokens; Enterprise =
  custom. LiveDocs is unmetered because it never calls a metered API — it reads your sources
  locally, private repos included, at no cost. Figures rot; the durable claim is the *structure*
  (metered SaaS vs unmetered local), so cite the structure and date any figure. context7's free
  tier is real, and its pre-indexed breadth is its home turf (conceded above).

## Honest reality: positioning ≠ winning

context7 leads on distribution, not fidelity. Better-but-niche loses to worse-but-universal.
A sharp message buys mindshare, not users. To compete we still need context7's winning half:

- Frictionless install. Already true: an MCP plus the `look-up` skill, one line to add.
- Presence where devs look: README, awesome-lists, being carried by default in other tools.
- Breadth for the long tail: generic discovery (`llms.txt`, registry, repo) plus a shared
  adapter marketplace that ships metadata, not content. Not a central cache.

## Wording guidance

Don't lead with "decentralized"; it reads abstract and buzzword-adjacent. Use "local / on
your machine / straight from the source / no index in between." Keep "decentralized" for the
architecture explanation.

## Candidate taglines

- "The docs your code actually runs on."
- "Latest docs, straight from the source, not a stale index."
- "Live docs. On your machine. No index, no API key, no lag."

## Anti-positioning (what NOT to build)

A central shared content cache would turn LiveDocs into context7: stale, crawl infra, lost
privacy. Speed comes from local ETag revalidation. The community effect comes from shared
routes and adapters, never shared content. See the boundary in
[primary-source-spectrum.md](wiki/Primary-Source-Spectrum.md).
