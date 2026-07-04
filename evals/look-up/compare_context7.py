#!/usr/bin/env python3
"""vs-context7 comparison harness (issue #27).

Measures ONE honest, structural axis: **latest-version freshness**. The neutral
oracle is the package registry's current version (the same fact both a live
fetcher and a pre-built index are trying to reflect).

- LiveDocs fetches the registry live, so its answer is checked *by computation*
  against the ground truth.
- context7 is a doc-snippet retriever ranked by coverage, not a version API. Its
  answer is prose (which entry ranked top, what version it was pinned to), so the
  sample records a *human judgment* of whether its default/top-ranked result
  reflects the current release. The harness trusts that recorded judgment rather
  than brittle-parsing prose.

Honesty guard (see README): this measures freshness only. context7 legitimately
wins on doc/snippet breadth, and often *has* the current version in a lower-ranked
entry — conceded explicitly. We do not measure coverage (a pre-built index's home
turf). If a run shows context7 current for some library, it is reported as such.

The comparison data is a dated snapshot in compare_context7_sample.json,
reproducible by re-running both MCP tools by hand (procedure in README). Pass
--verify-live to re-fetch registry ground truth and warn on drift.
"""
import argparse
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE_PATH = os.path.join(HERE, "compare_context7_sample.json")


def version_matches(answer, ground_truth):
    """True iff the ground-truth version appears as a whole release token in the answer.

    Boundary rules (fixed per #27 verify):
    - not preceded by a digit or `digit.` — so we match the whole number and a
      *suffix* of a longer version does NOT match (searching `19.2.7` must miss
      `1.19.2.7`), while a `v`/`@`/space prefix is fine (`v19.2.7`, `react@19.2.7`);
    - not followed by a digit, and not followed by `.<digit>` — so a *prefix* of a
      longer release does NOT match (searching `8.1` must miss `8.1.3`), while a
      trailing sentence period is fine (`19.2.7.` matches `19.2.7`).
    """
    if not answer or not ground_truth:
        return False
    pattern = r"(?<!\d)(?<!\d\.)" + re.escape(ground_truth) + r"(?!\d)(?!\.\d)"
    return re.search(pattern, answer) is not None


def judge_row(entry):
    """Turn one sample entry into a comparison row.

    livedocs_current is COMPUTED (answer vs ground truth); context7_current is the
    RECORDED judgment. Missing ground truth → livedocs_current is None (unknown).
    """
    gt = entry.get("ground_truth")
    livedocs = entry.get("livedocs") or {}
    context7 = entry.get("context7") or {}
    livedocs_current = version_matches(livedocs.get("answer", ""), gt) if gt else None
    # Symmetric with livedocs: a MISSING context7 judgment is unknown (None),
    # not silently scored as stale (#27 verify — fairness fix).
    c7_raw = context7.get("is_current")
    context7_current = None if c7_raw is None else bool(c7_raw)
    return {
        "id": entry.get("id"),
        "library": entry.get("library"),
        "ground_truth": gt,
        "livedocs_answer": livedocs.get("answer"),
        "livedocs_current": livedocs_current,
        "context7_answer": context7.get("answer"),
        "context7_current": context7_current,
    }


def tally(rows):
    """Aggregate is_current counts over the *contested* set — rows where BOTH tools
    have a known judgment. Symmetric: an unknown on either side excludes the row from
    the shared denominator, so incomplete data never silently favors either tool."""
    scored = [r for r in rows
              if r.get("livedocs_current") is not None and r.get("context7_current") is not None]
    return {
        "n": len(scored),
        "livedocs_current": sum(1 for r in scored if r["livedocs_current"]),
        "context7_current": sum(1 for r in scored if r["context7_current"]),
    }


def _cell(current):
    if current is None:
        return "—"
    return "✅ current" if current else "⚠️ stale"


def render_table(rows):
    lines = [
        "| library | registry (truth) | LiveDocs | context7 (default match) |",
        "|---------|------------------|----------|--------------------------|",
    ]
    for r in rows:
        # Escape any literal pipe in the free-text context7 answer so it can't break
        # out of the markdown cell (#27 verify — robustness).
        c7 = (r["context7_answer"] or "").replace("|", "\\|")
        lines.append(
            f"| {r['library']} | `{r['ground_truth']}` | "
            f"{_cell(r['livedocs_current'])} (`{r['livedocs_answer']}`) | "
            f"{_cell(r['context7_current'])} ({c7}) |"
        )
    return "\n".join(lines)


# ── vs-context7 README front-page block (issue #46) ───────────────────────────
# The README block is MACHINE-PRODUCED from the dated snapshot, never hand-edited:
# a competitive number in prose that drifts becomes an *asserted* claim, which the
# project iron rule forbids (measured, never asserted — #27/#29). Sentinels delimit
# the block; `--emit-readme --check` turns drift into a failure.
README_BEGIN = "<!-- BEGIN vs-context7 (generated: compare_context7.py --emit-readme --write — do not hand-edit) -->"
README_END = "<!-- END vs-context7 -->"
# Single sentinel-to-sentinel matcher, reused by every path that reads/writes the
# block so they can never diverge. Non-greedy + DOTALL: one block spans newlines
# but stops at the first END (#46 verify — a crafted captured_at can't smuggle an
# END either; render_readme_block validates the date shape first).
_SENTINEL_RE = re.compile(re.escape(README_BEGIN) + r".*?" + re.escape(README_END), re.DOTALL)
# captured_at must be exactly an ISO date — rejects a missing/blank date (which would
# ship "captured None") AND any value carrying markup/sentinels (injection guard).
_ISO_DATE_RE = re.compile(r"\A\d{4}-\d{2}-\d{2}\Z")


def _sole_block(readme_text):
    """Return the one sentinel-delimited block's text, or raise if there is not
    EXACTLY one. Exactly-one is the invariant the drift guard rests on: a first-match
    `re.search` would let a second, stale block slip past `--check` undetected (#46 verify)."""
    blocks = _SENTINEL_RE.findall(readme_text)
    if len(blocks) != 1:
        raise ValueError(
            f"expected exactly one vs-context7 sentinel block in README, found {len(blocks)}"
        )
    return blocks[0]


def render_bar_chart(t, captured_at, width=26):
    """Unicode bar chart of latest-version freshness over the *contested* set.

    Pure: takes the tally() dict (n / livedocs_current / context7_current) + a
    capture date, returns a plain-text block. Bar length is proportional to
    count/n, so the visual can never contradict the number it labels. The honesty
    caveat is part of the returned block — it cannot be separated from the chart.
    """
    n = t["n"]

    def bar(count):
        filled = round(width * count / n) if n else 0
        filled = max(0, min(filled, width))   # defensive: a malformed tally can't overflow the bar
        return "█" * filled + "░" * (width - filled)

    lo, c7 = t["livedocs_current"], t["context7_current"]
    return "\n".join([
        f"latest-version freshness · contested set ({n} fast-moving libs) · captured {captured_at}",
        f"  LiveDocs  {bar(lo)}  {lo}/{n}",
        f"  context7  {bar(c7)}  {c7}/{n}",
        "  freshness only · context7 wins coverage · LiveDocs current by construction · measured, not asserted",
    ])


def render_readme_block(rows, captured_at):
    """The full sentinel-delimited README section: the bar chart in a fenced code
    block + a one-line pointer to the harness. Reuses tally() so the chart and the
    CLI summary can never disagree.

    Refuses to emit unless captured_at is a bare ISO date — a competitive claim on the
    front page must carry a real date, and this also blocks a crafted snapshot from
    injecting markup / a stray END sentinel into the block (#46 verify)."""
    if not _ISO_DATE_RE.match(str(captured_at) if captured_at is not None else ""):
        raise ValueError(
            f"captured_at must be an ISO date (YYYY-MM-DD); got {captured_at!r}. "
            "Refusing to emit a README competitive claim with a missing/malformed date."
        )
    chart = render_bar_chart(tally(rows), captured_at)
    return "\n".join([
        README_BEGIN,
        "```text",
        chart,
        "```",
        "_Measured by `evals/look-up/compare_context7.py` from a dated snapshot — "
        "freshness only, on deliberately fast-moving libs; context7 wins on coverage. "
        "Regenerate: `python3 evals/look-up/compare_context7.py --emit-readme --write`._",
        README_END,
    ])


def readme_path():
    """Absolute path to the repo-root README (two levels up from this file)."""
    return os.path.abspath(os.path.join(HERE, "..", "..", "README.md"))


def replace_readme_block(readme_text, new_block):
    """Return readme_text with its (single) sentinel-delimited vs-context7 block
    replaced. Raises ValueError unless EXACTLY one block is present — never silently
    appends, never leaves a second stale block behind (#46 verify)."""
    _sole_block(readme_text)   # assert exactly one; raises otherwise
    # lambda replacement avoids re interpreting backslashes / group refs in new_block
    return _SENTINEL_RE.sub(lambda _m: new_block, readme_text, count=1)


def _atomic_write(path, text):
    """Write text to path via a temp file + os.replace so an interrupted write never
    leaves README.md truncated (#46 verify)."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_sample(path=SAMPLE_PATH):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main(argv=None):
    ap = argparse.ArgumentParser(description="LiveDocs vs context7 freshness comparison (#27)")
    ap.add_argument("--sample", default=SAMPLE_PATH, help="path to the dated comparison sample")
    ap.add_argument("--json", action="store_true", help="emit the result summary as JSON")
    ap.add_argument("--verify-live", action="store_true",
                    help="re-fetch registry ground truth and warn if the recorded snapshot drifted")
    ap.add_argument("--emit-readme", action="store_true",
                    help="emit the README vs-context7 block (bar chart); compose with --write / --check")
    ap.add_argument("--write", action="store_true",
                    help="with --emit-readme: rewrite the sentinel-marked block in README.md in place")
    ap.add_argument("--check", action="store_true",
                    help="with --emit-readme: exit 1 if README's block drifted from the snapshot (fail-loud guard)")
    args = ap.parse_args(argv)

    # --write / --check are modifiers of --emit-readme; without it they silently
    # no-op'd and a mis-invoked `--check` guard exited 0 (false pass, #46 verify).
    if (args.check or args.write) and not args.emit_readme:
        ap.error("--check / --write require --emit-readme")

    sample = load_sample(args.sample)
    results = sample.get("results", [])
    rows = [judge_row(e) for e in results]

    if args.emit_readme:
        block = render_readme_block(rows, sample.get("captured_at"))
        path = readme_path()
        if args.check:
            with open(path, encoding="utf-8") as f:
                current = f.read()
            try:
                committed = _sole_block(current)   # exactly one block, or fail loud
            except ValueError as exc:
                print(f"✗ {exc} — run: python3 evals/look-up/compare_context7.py --emit-readme --write",
                      file=sys.stderr)
                return 1
            if committed.strip() != block.strip():
                print("✗ README vs-context7 block is stale — run: "
                      "python3 evals/look-up/compare_context7.py --emit-readme --write", file=sys.stderr)
                return 1
            print("✓ README vs-context7 block in sync")
            return 0
        if args.write:
            with open(path, encoding="utf-8") as f:
                current = f.read()
            _atomic_write(path, replace_readme_block(current, block))   # raises unless exactly one block
            print(f"✓ wrote vs-context7 block to {path}")
            return 0
        print(block)
        return 0

    if args.verify_live:
        from oracle import fetch_latest_version
        print("note: --verify-live re-checks the registry (LiveDocs' ground truth) only; "
              "context7's recorded judgments are a dated snapshot, not re-fetched here.",
              file=sys.stderr)
        for e, r in zip(results, rows):
            lib, eco = e.get("library"), e.get("ecosystem")
            if not lib or not eco:
                continue
            live = fetch_latest_version(lib, eco)
            if live and live != r["ground_truth"]:
                print(f"⚠ drift: {lib} recorded {r['ground_truth']} but registry now {live}",
                      file=sys.stderr)

    t = tally(rows)
    if args.json:
        print(json.dumps({"captured_at": sample.get("captured_at"), "tally": t, "rows": rows}, indent=2))
        return 0

    print(f"# LiveDocs vs context7 — freshness on fast-moving libs (captured {sample.get('captured_at')})\n")
    print(render_table(rows))
    print(
        f"\n**Reflects the current release (registry = ground truth, {t['n']} fast-moving libs):** "
        f"LiveDocs {t['livedocs_current']}/{t['n']} (live registry, by construction) · "
        f"context7 default match {t['context7_current']}/{t['n']}."
    )
    print("\nHonesty note: freshness only, on libraries picked *because* they move fast — a "
          "re-crawled index's hardest case, not a neutral sample. LiveDocs' side is the registry "
          "by construction (it fetches it live), so the finding is really context7's default-match "
          "staleness. context7 wins on doc/snippet breadth (not measured) and can carry the "
          "current version in a lower-ranked entry (react, in this sample).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
