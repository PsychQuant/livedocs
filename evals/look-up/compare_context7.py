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
wins on doc/snippet breadth, and *can* have the current version in a lower-ranked
entry (as with react in the sample — the other five do not) — conceded explicitly.
We do not measure coverage (a pre-built index's home turf). If a run shows context7
current for some library, it is reported as such.

The comparison data is a dated snapshot in compare_context7_sample.json,
reproducible by re-running both MCP tools by hand (procedure in README). Pass
--verify-live to re-fetch registry ground truth — it exits 1 on drift or when any
library could not be verified (#49); --check-staleness bounds the snapshot's age.
"""
import argparse
import datetime
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


def _sole_block(readme_text):
    """Return the one sentinel-delimited block's text, or raise unless there is EXACTLY
    one WELL-FORMED block. Counting only complete BEGIN…END pairs missed an orphaned
    BEGIN (a stale chart with no END still renders on GitHub yet passed `--check`), so
    also require the raw BEGIN/END occurrence counts to be 1 (#46 verify round 2)."""
    begins = readme_text.count(README_BEGIN)
    ends = readme_text.count(README_END)
    blocks = _SENTINEL_RE.findall(readme_text)
    if not (begins == ends == len(blocks) == 1):
        raise ValueError(
            f"expected exactly one well-formed vs-context7 sentinel block in README "
            f"(found {begins} BEGIN, {ends} END, {len(blocks)} complete)"
        )
    return blocks[0]


def _require_iso_date(value):
    """Raise unless value is a real ISO calendar date (YYYY-MM-DD, ASCII). The date is
    the only free-text field reaching the front-page block, so this guards the 'dated'
    claim: it rejects None / "captured None" / markup-injection AND calendar-impossible
    dates (2026-99-99) via a `date.fromisoformat` round-trip — which also forbids the
    Unicode digits a shape-only regex would accept (#46 verify round 2)."""
    s = value if isinstance(value, str) else ""
    try:
        if s != datetime.date.fromisoformat(s).isoformat():
            raise ValueError
    except (ValueError, TypeError):
        raise ValueError(
            f"captured_at must be a real ISO date (YYYY-MM-DD); got {value!r}. "
            "Refusing to emit a README competitive claim with a missing/malformed date."
        )


def staleness_days(captured_at, today):
    """Days elapsed since the snapshot's captured_at (#49). Pure: `today` is INJECTED
    (a datetime.date) so tests and the CLI's --today flag never read the wall clock —
    a wall-clock assertion would itself become the time bomb this exists to catch.
    Validates captured_at with the same ISO-calendar round-trip as the README guard."""
    _require_iso_date(captured_at)
    return (today - datetime.date.fromisoformat(captured_at)).days


CHART_ASSET = "docs/assets/vs-context7-freshness.svg"


def chart_asset_path():
    """Absolute path to the committed SVG chart asset (repo-root relative)."""
    return os.path.abspath(os.path.join(HERE, "..", "..", *CHART_ASSET.split("/")))


def render_readme_block(rows, captured_at):
    """The sentinel-delimited README section (issue #50): the per-library matplotlib
    SVG embedded as an image + a VISIBLE caption carrying the honesty caveats and the
    capture date. The competitive numbers live IN the SVG (drift-guarded by chart.py's
    version-token test); this block guards the caption / date / embed path.

    Refuses to emit unless captured_at is a bare ISO date — a front-page competitive
    claim must carry a real date, and this blocks a crafted snapshot from injecting
    markup into the caption (#46 verify)."""
    _require_iso_date(captured_at)
    t = tally(rows)
    lc, cc, n = t["livedocs_current"], t["context7_current"], t["n"]
    alt = (f"Per-library latest-version freshness on {n} fast-moving libraries: "
           f"LiveDocs returns the current release on {lc}/{n}; context7's default match on {cc}/{n} "
           f"(freshness only, context7 wins on coverage).")
    return "\n".join([
        README_BEGIN,
        f"![{alt}]({CHART_ASSET})",
        "",
        f"_**Latest-version freshness**, {n} fast-moving libraries · captured {captured_at} · "
        "**measured, not asserted**: freshness of the *default match* only — context7 wins on doc coverage "
        "and can carry the current version in a lower-ranked entry (as with react here; both conceded, not measured), "
        "the libraries are forward-selected fast-movers, and LiveDocs is the registry by construction. "
        "Data + method: [`evals/look-up`](https://github.com/PsychQuant/livedocs/tree/main/evals/look-up)._",
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
        try:   # mkstemp is 0600; preserve the target's mode so README isn't dropped to owner-only
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        except OSError:
            pass
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
                    help="emit the README vs-context7 block (SVG image embed + caption); compose with --write / --check")
    ap.add_argument("--emit-chart", action="store_true",
                    help="emit the per-library SVG chart asset (issue #50); compose with --write / --check")
    ap.add_argument("--check-staleness", action="store_true",
                    help="exit 1 if the snapshot's captured_at is older than --max-age-days (#49; "
                         "run by the scheduled freshness workflow, NOT PR CI — a time-based failure "
                         "must never redden unrelated PRs)")
    ap.add_argument("--max-age-days", type=int, default=120,
                    help="staleness budget in days for --check-staleness (default: 120)")
    ap.add_argument("--today", default=None,
                    help="ISO date override for --check-staleness (tests / reproducing a cron run); "
                         "defaults to the wall clock")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true",
                      help="with --emit-readme / --emit-chart: rewrite the target file in place")
    mode.add_argument("--check", action="store_true",
                      help="with --emit-readme / --emit-chart: exit 1 if the committed artifact drifted (fail-loud guard)")
    args = ap.parse_args(argv)

    if args.emit_readme and args.emit_chart:
        ap.error("--emit-readme and --emit-chart are separate artifacts; pass one at a time")
    # --write / --check are modifiers of an --emit-* mode; alone they silently
    # no-op'd and a mis-invoked `--check` guard exited 0 (false pass, #46 verify).
    if (args.check or args.write) and not (args.emit_readme or args.emit_chart):
        ap.error("--check / --write require --emit-readme or --emit-chart")

    sample = load_sample(args.sample)
    results = sample.get("results", [])
    rows = [judge_row(e) for e in results]

    if args.check_staleness:
        captured = sample.get("captured_at")
        try:
            if args.today:
                # Same strict ISO-calendar round-trip as captured_at — Python 3.11+'s bare
                # fromisoformat is lenient (accepts e.g. "20260702"), which would let a
                # mistyped override silently parse (#49 verify round 1).
                _require_iso_date(args.today)
                today = datetime.date.fromisoformat(args.today)
            else:
                today = datetime.date.today()
        except (ValueError, TypeError):
            print(f"✗ --today must be an ISO date (YYYY-MM-DD); got {args.today!r}", file=sys.stderr)
            return 1
        try:
            age = staleness_days(captured, today)
        except ValueError as exc:
            print(f"✗ {exc}", file=sys.stderr)
            return 1
        if age < 0:
            print(f"✗ captured_at {captured} is in the FUTURE of {today} — clock or snapshot error",
                  file=sys.stderr)
            return 1
        if age > args.max_age_days:
            print(f"✗ snapshot is {age} days old (captured {captured}; budget {args.max_age_days}d) — "
                  "the front-page competitive claim is rotting into an ASSERTED number (#27/#29). "
                  "Refresh per evals/look-up/README.md § Refreshing the snapshot.", file=sys.stderr)
            return 1
        print(f"✓ snapshot age {age}d is within the {args.max_age_days}d budget (captured {captured})")
        return 0

    if args.emit_chart:
        from chart import render_svg
        svg = render_svg(sample)
        path = chart_asset_path()
        if args.check:
            if not os.path.exists(path):
                print(f"✗ chart asset missing ({CHART_ASSET}) — run --emit-chart --write", file=sys.stderr)
                return 1
            with open(path, encoding="utf-8") as f:
                committed = f.read()
            if committed != svg:
                print(f"✗ {CHART_ASSET} is stale — run: "
                      "python3 evals/look-up/compare_context7.py --emit-chart --write", file=sys.stderr)
                return 1
            print(f"✓ {CHART_ASSET} in sync")
            return 0
        if args.write:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            _atomic_write(path, svg)
            print(f"✓ wrote {CHART_ASSET}")
            return 0
        sys.stdout.write(svg)
        return 0

    if args.emit_readme:
        block = render_readme_block(rows, sample.get("captured_at"))
        path = readme_path()
        if args.check:
            with open(path, encoding="utf-8") as f:
                current = f.read()
            try:
                committed = _sole_block(current)   # exactly one well-formed block, or fail loud
            except ValueError as exc:
                print(f"✗ {exc} — restore the sentinel block by hand, then re-run --emit-readme --write",
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
            try:
                new_text = replace_readme_block(current, block)   # raises unless exactly one well-formed block
            except ValueError as exc:
                print(f"✗ {exc} — restore the sentinel block by hand, then re-run --write", file=sys.stderr)
                return 1
            _atomic_write(path, new_text)
            print(f"✓ wrote vs-context7 block to {path}")
            return 0
        print(block)
        return 0

    if args.verify_live:
        from oracle import fetch_latest_version
        print("note: --verify-live re-checks the registry (LiveDocs' ground truth) only; "
              "context7's recorded judgments are a dated snapshot, not re-fetched here.",
              file=sys.stderr)
        drifted, verified, unverified = 0, 0, 0
        for e, r in zip(results, rows):
            lib, eco = e.get("library"), e.get("ecosystem")
            if not lib or not eco:
                continue
            live = fetch_latest_version(lib, eco)
            if not live:
                # fetch_latest_version returns None on network failure OR an ecosystem it
                # doesn't support — either way this library was NOT verified. Silently
                # treating that as "no drift" made a registry outage a false GREEN
                # (#49 verify round 1): green must provably mean "all checked, none drifted".
                unverified += 1
                print(f"⚠ unverified: could not fetch a live version for {lib} ({eco}) — "
                      "registry unreachable or unsupported ecosystem", file=sys.stderr)
                continue
            verified += 1
            if live != r["ground_truth"]:
                drifted += 1
                print(f"⚠ drift: {lib} recorded {r['ground_truth']} but registry now {live}",
                      file=sys.stderr)
        # Fail LOUD (#49): a run that only prints warnings to an unread log is not a
        # signal. Green must mean "verified all N, none drifted" — drift AND
        # couldn't-verify both exit 1, with distinct messages.
        print(f"verified {verified} of {len(results)} recorded ground truths "
              f"({drifted} drifted, {unverified} unverified)", file=sys.stderr)
        if drifted:
            print(f"✗ {drifted} of {len(results)} recorded ground truths have drifted — "
                  "refresh the snapshot per evals/look-up/README.md § Refreshing the snapshot.",
                  file=sys.stderr)
            return 1
        if unverified:
            print(f"✗ {unverified} of {len(results)} libraries could not be verified — "
                  "nothing was proven about them; re-run when the registry is reachable "
                  "(or add oracle support for the ecosystem).", file=sys.stderr)
            return 1

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
