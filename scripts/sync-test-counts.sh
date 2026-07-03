#!/usr/bin/env bash
# Sync every REGISTERED doc reference to the ACTUAL test counts, and FAIL LOUDLY
# on any inconsistency instead of silently shipping stale numbers. This is the
# machine step for the test-count-sync discipline (CLAUDE.md: "regressed twice in
# one day") — run it after every test add/remove.
#
# What it OWNS:     the headline totals, the `## Swift`/`## Python` suite totals,
#                   the code-block comment counts, and the README breakdown.
# What it VERIFIES: the `### <Target> — N` section subtotals and the per-file
#                   table rows you hand-edit — it asserts rows sum to their
#                   subtotal and subtotals sum to the suite total, and ABORTS
#                   (writing nothing) if not, so a forgotten row surfaces as a
#                   failure, never a silent same-page contradiction.
# What it does NOT touch: historical/milestone prose (e.g. "grew 72 → 110 during
#                   the v0.7.0 hardening") — those are facts, not live counts.
#
# LIMITATION: it only knows the phrasings in the `edits` map + the two Testing
# tables. A test count written in a NEW phrasing/file is invisible to it — add
# the phrasing here when you introduce one (the "✓ ... registered references"
# message is scoped accordingly, not a claim about every number in the repo).
#
# Usage:  bash scripts/sync-test-counts.sh   (then review `git diff` and commit)
set -uo pipefail   # NOT -e: we check exit codes explicitly to give friendly errors
cd "$(git rev-parse --show-toplevel)" || { echo "✗ not in a git repo" >&2; exit 1; }

# ── Derive counts by RUNNING both suites; a red suite aborts (never mints a
#    false "all green") ─────────────────────────────────────────────────────────
echo "Running swift test…"
SWIFT_OUT=$(swift test 2>&1)
if [ $? -ne 0 ]; then
  echo "✗ swift test FAILED — refusing to stamp 'all green'." >&2
  printf '%s\n' "$SWIFT_OUT" | tail -20 >&2; exit 1
fi
# Grand total = the 'Executed N tests, with 0 failures' line for the top-level
# 'All tests' suite; it is the largest such N (sum over all bundles).
SWIFT=$(printf '%s\n' "$SWIFT_OUT" \
  | grep -oE 'Executed [0-9]+ tests, with 0 failures' \
  | grep -oE '[0-9]+' | sort -n | tail -1)

echo "Running pytest…"
PY_OUT=$(python3 -m pytest evals/look-up/tests/ -q 2>&1)
if [ $? -ne 0 ]; then
  echo "✗ pytest FAILED — refusing to stamp 'all green'." >&2
  printf '%s\n' "$PY_OUT" | tail -20 >&2; exit 1
fi
# Count ALL collected test functions (what the per-file table rows count), i.e.
# passed + skipped + xfailed + xpassed — so a skip doesn't undercount vs the rows.
PYTHON=$(printf '%s\n' "$PY_OUT" \
  | grep -oE '[0-9]+ (passed|skipped|xfailed|xpassed)' \
  | grep -oE '^[0-9]+' | paste -sd+ - | bc)

if ! [ "${SWIFT:-0}" -gt 0 ] 2>/dev/null || ! [ "${PYTHON:-0}" -gt 0 ] 2>/dev/null; then
  echo "✗ could not parse counts (Swift='${SWIFT:-}' Python='${PYTHON:-}') — output format changed?" >&2
  exit 1
fi
TOTAL=$(( SWIFT + PYTHON ))
echo "Derived (both suites green): Swift=$SWIFT  Python=$PYTHON  Total=$TOTAL"

PYTHONIOENCODING=utf-8 SWIFT="$SWIFT" PYTHON="$PYTHON" TOTAL="$TOTAL" python3 - <<'PY'
import os, re, sys
S, P, T = int(os.environ["SWIFT"]), int(os.environ["PYTHON"]), int(os.environ["TOTAL"])
errors = []

# ── PHASE 1 (read-only): verify the hand-edited section subtotals + per-file
#    table rows are internally consistent with the derived suite totals. Runs
#    BEFORE any write, so a failure leaves the tree untouched (usable as a pure
#    drift check, and never half-syncs). ──────────────────────────────────────
def check_consistency(path):
    if not os.path.exists(path):
        errors.append(f"{path}: target file missing (a rename? update this script)")
        return
    cur_suite = None                          # 'swift' | 'python' | None
    cur_sub = None                            # [name, claimed, rowsum]
    subtotals = {"swift": [], "python": []}
    row_only = {"swift": 0, "python": 0}      # rows not under a ### (Python side)
    in_fence = False
    h2    = re.compile(r"^##\s+(.+)")                       # ANY "## …" heading
    suite = re.compile(r"^(Swift|Python)\s+—\s+\d+", re.I)  # a suite total heading
    h3    = re.compile(r"^###\s+`?([\w.\-]+)`?\s+—\s+(\d+)\b")
    h3any = re.compile(r"^###\s")
    row   = re.compile(r"^\|\s*`([\w.\-]+)`\s*\|\s*(\d+)\s*\|")
    def flush():
        if cur_sub and cur_suite:
            subtotals[cur_suite].append(tuple(cur_sub))
    for ln in open(path, encoding="utf-8").read().splitlines():
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence; continue
        if in_fence:
            continue
        m2 = h2.match(ln)
        if m2:
            # Any `##` heading ends the current suite section. Only a "Swift — N"
            # / "Python — N" heading (re)opens one; anything else (## CI, ##
            # Discipline, …) sets cur_suite=None so its tables can't leak in.
            flush(); cur_sub = None
            sm = suite.match(m2.group(1))
            cur_suite = sm.group(1).lower() if sm else None
            continue
        if h3any.match(ln):
            flush(); cur_sub = None
            m3 = h3.match(ln)
            if m3 and cur_suite:
                cur_sub = [m3.group(1), int(m3.group(2)), 0]
            # a `###` that isn't a clean subtotal ends the prior section's rows
            # (do NOT keep leaking rows into it)
            continue
        mr = row.match(ln)
        if mr and cur_suite:
            n = int(mr.group(2))
            if cur_sub: cur_sub[2] += n
            else:       row_only[cur_suite] += n
    flush()
    for suite_name in ("swift", "python"):
        for name, claimed, rowsum in subtotals[suite_name]:
            if claimed != rowsum:
                errors.append(f"{path}: subtotal '### {name} — {claimed}' != sum of its rows ({rowsum})")
    for suite_name, total in (("swift", S), ("python", P)):
        contrib = sum(c for _, c, _ in subtotals[suite_name]) + row_only[suite_name]
        if contrib != total:
            errors.append(f"{path}: {suite_name} per-file counts sum to {contrib}, "
                          f"but the derived {suite_name} total is {total} — a row/subtotal is stale")

for f in ("docs/wiki/Testing.md", "docs/wiki/Testing-zh-TW.md"):
    check_consistency(f)

if errors:
    print("\n✗ test-count consistency FAILED (nothing written) — fix these and re-run:", file=sys.stderr)
    for e in errors: print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

# ── PHASE 2 (write): own the TOTALS. Each entry (regex, replacement, min_hits);
#    a fixed reference matching fewer than min_hits means the phrasing drifted →
#    FAILURE, not a silent skip. Historical/milestone prose is deliberately NOT
#    listed here. ───────────────────────────────────────────────────────────────
edits = {
  "docs/wiki/Testing.md": [
    (r"\*\*\d+ tests, all green\*\*", f"**{T} tests, all green**", 1),
    (r"(swift test\s+#\s*)\d+( Swift tests)", rf"\g<1>{S}\g<2>", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( Python eval tests)", rf"\g<1>{P}\g<2>", 1),
    (r"## Swift — \d+ tests", f"## Swift — {S} tests", 1),
    (r"## Python — \d+ tests", f"## Python — {P} tests", 1),
  ],
  "docs/wiki/Testing-zh-TW.md": [
    (r"\*\*\d+ 個 test,全綠\*\*", f"**{T} 個 test,全綠**", 1),
    (r"(swift test\s+#\s*)\d+( 個 Swift test)", rf"\g<1>{S}\g<2>", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( 個 Python eval test)", rf"\g<1>{P}\g<2>", 1),
    (r"## Swift — \d+ 個 test", f"## Swift — {S} 個 test", 1),
    (r"## Python — \d+ 個 test", f"## Python — {P} 個 test", 1),
  ],
  "docs/wiki/Home.md": [
    (r"\(\d+ tests\) and what each covers", f"({T} tests) and what each covers", 1),
  ],
  "docs/wiki/Home-zh-TW.md": [
    (r"測試套件（\d+ 個 test）", f"測試套件（{T} 個 test）", 1),
  ],
  "README.md": [
    (r"suite breakdown \(\d+ tests: \d+ Swift \+ \d+ Python\)",
     f"suite breakdown ({T} tests: {S} Swift + {P} Python)", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( harness unit tests)", rf"\g<1>{P}\g<2>", 1),
  ],
  "CLAUDE.md": [
    (r"(swift test\s+#\s*)\d+( Swift tests \(no network\))", rf"\g<1>{S}\g<2>", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( Python tests \(no API calls\))", rf"\g<1>{P}\g<2>", 1),
  ],
}
for path, pairs in edits.items():
    if not os.path.exists(path):
        errors.append(f"{path}: target file missing"); continue
    before = open(path, encoding="utf-8").read(); s = before
    for rx, rep, min_hits in pairs:
        s, n = re.subn(rx, rep, s)
        if n < min_hits:
            errors.append(f"{path}: pattern {rx!r} matched {n}x, expected >= {min_hits} (phrasing drifted)")
    if s != before:
        open(path, "w", encoding="utf-8").write(s); print(f"  {path}: updated")
    else:
        print(f"  {path}: already in sync")

if errors:
    print("\n✗ some registered references drifted — repair them and re-run:", file=sys.stderr)
    for e in errors: print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
print(f"\n✓ registered references synced to {T} ({S} Swift + {P} Python); subtotals + rows consistent.")
PY
rc=$?
[ $rc -eq 0 ] && echo "Review 'git diff', then commit:  docs: sync test counts to ${TOTAL} (${SWIFT} Swift + ${PYTHON} Python)"
exit $rc
