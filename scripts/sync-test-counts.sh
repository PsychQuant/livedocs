#!/usr/bin/env bash
# Sync every doc reference to the ACTUAL test counts, and FAIL LOUDLY on any
# inconsistency instead of silently shipping stale numbers. This is the machine
# step for the test-count-sync discipline (CLAUDE.md: "regressed twice in one
# day") — run it after every test add/remove.
#
# What it owns:  the headline totals, the `## Swift`/`## Python` suite totals,
#                the code-block comment counts, and the README breakdown.
# What it VERIFIES (but does not own — you hand-edit these):
#                the `### <Target> — N` section subtotals and the per-file table
#                rows. The script asserts rows sum to their subtotal and subtotals
#                sum to the suite total, and ABORTS if not — so a forgotten row
#                update surfaces as a failure, never a silent contradiction.
#
# Usage:  bash scripts/sync-test-counts.sh   (then review `git diff` and commit)
#
# Adding a NEW doc reference to a test count? Add its phrasing to the `edits`
# map below (with an expected hit count) so this guard stays complete.
set -uo pipefail   # NOT -e: we check exit codes explicitly to give friendly errors
cd "$(git rev-parse --show-toplevel)"

# ── Derive counts by RUNNING both suites (a red suite must abort, never mint
#    a false "all green") ───────────────────────────────────────────────────────
echo "Running swift test…"
SWIFT_OUT=$(swift test 2>&1)
if [ $? -ne 0 ]; then
  echo "✗ swift test FAILED — refusing to stamp 'all green'." >&2
  printf '%s\n' "$SWIFT_OUT" | tail -20 >&2
  exit 1
fi
# The grand total is the 'Executed N tests, with 0 failures' line for the
# top-level 'All tests' suite; it is the largest such N (sum of all bundles).
SWIFT=$(printf '%s\n' "$SWIFT_OUT" \
  | grep -oE 'Executed [0-9]+ tests, with 0 failures' \
  | grep -oE '[0-9]+' | sort -n | tail -1)

echo "Running pytest…"
PY_OUT=$(python3 -m pytest evals/look-up/tests/ -q 2>&1)
if [ $? -ne 0 ]; then
  echo "✗ pytest FAILED — refusing to stamp 'all green'." >&2
  printf '%s\n' "$PY_OUT" | tail -20 >&2
  exit 1
fi
PYTHON=$(printf '%s\n' "$PY_OUT" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1)

if ! [ "${SWIFT:-0}" -gt 0 ] 2>/dev/null || ! [ "${PYTHON:-0}" -gt 0 ] 2>/dev/null; then
  echo "✗ could not parse counts (Swift='${SWIFT:-}' Python='${PYTHON:-}') — output format changed?" >&2
  exit 1
fi
TOTAL=$(( SWIFT + PYTHON ))
echo "Derived (both suites green): Swift=$SWIFT  Python=$PYTHON  Total=$TOTAL"

SWIFT="$SWIFT" PYTHON="$PYTHON" TOTAL="$TOTAL" python3 - <<'PY'
import os, re, sys
S, P, T = int(os.environ["SWIFT"]), int(os.environ["PYTHON"]), int(os.environ["TOTAL"])
errors = []

# ── 1. Own the TOTALS. Each entry: (regex, replacement, min_hits). A fixed
#    reference that matches fewer than min_hits means the phrasing drifted (or a
#    file was renamed) — that is a FAILURE, not a silent skip. ────────────────────
edits = {
  "docs/wiki/Testing.md": [
    (r"\*\*\d+ tests, all green\*\*", f"**{T} tests, all green**", 1),
    (r"(swift test\s+#\s*)\d+( Swift tests)", rf"\g<1>{S}\g<2>", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( Python eval tests)", rf"\g<1>{P}\g<2>", 1),
    (r"## Swift — \d+ tests", f"## Swift — {S} tests", 1),
    (r"## Python — \d+ tests", f"## Python — {P} tests", 1),
    (r"(grew 72 → )\d+( Swift tests)", rf"\g<1>{S}\g<2>", 1),
    (r"(0 → )\d+( for the Python evals)", rf"\g<1>{P}\g<2>", 1),
  ],
  "docs/wiki/Testing-zh-TW.md": [
    (r"\*\*\d+ 個 test,全綠\*\*", f"**{T} 個 test,全綠**", 1),
    (r"(swift test\s+#\s*)\d+( 個 Swift test)", rf"\g<1>{S}\g<2>", 1),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( 個 Python eval test)", rf"\g<1>{P}\g<2>", 1),
    (r"## Swift — \d+ 個 test", f"## Swift — {S} 個 test", 1),
    (r"## Python — \d+ 個 test", f"## Python — {P} 個 test", 1),
    (r"(從 72 → )\d+", rf"\g<1>{S}", 1),
    (r"(Python eval 從 0 → )\d+", rf"\g<1>{P}", 1),
  ],
  # Anchored to the surrounding Guides-line text so no unrelated "(N tests)" /
  # "（N 個 test）" elsewhere can be caught.
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
        errors.append(f"{path}: target file missing (a rename? update this script)")
        continue
    before = open(path, encoding="utf-8").read()
    s = before
    for rx, rep, min_hits in pairs:
        s, n = re.subn(rx, rep, s)
        if n < min_hits:
            errors.append(f"{path}: pattern {rx!r} matched {n} time(s), expected >= {min_hits} "
                          f"(phrasing drifted — add/repair the reference)")
    if s != before:
        open(path, "w", encoding="utf-8").write(s)
        print(f"  {path}: updated")
    else:
        print(f"  {path}: already in sync")

# ── 2. VERIFY the section subtotals + per-file table rows (which stay
#    hand-edited) are internally consistent with the derived suite totals. This
#    catches the "## Swift — 144 but ### subtotals still 99+11=110" contradiction
#    that a totals-only sync would otherwise ship silently. ─────────────────────
def check_consistency(path, swift_total, py_total):
    if not os.path.exists(path):
        return
    lines = open(path, encoding="utf-8").read().splitlines()
    # section header: "## Swift — N tests" / "## Python — N ..." (locale-agnostic on the number)
    # subtotal header: "### `Target` — N ..."
    # table row:       "| `File` | N | ... |"
    cur_suite = None            # 'swift' | 'python' | None
    cur_sub = None              # (name, claimed_subtotal, running_row_sum)
    subtotals = {"swift": [], "python": []}   # list of (name, claimed, rowsum)
    row_only_sum = {"swift": 0, "python": 0}  # rows not under a ### (python side)
    h2 = re.compile(r"^##\s+(Swift|Python)\s+—\s+\d+")
    h3 = re.compile(r"^###\s+`?([\w.]+)`?\s+—\s+(\d+)")
    row = re.compile(r"^\|\s*`([\w.]+)`\s*\|\s*(\d+)\s*\|")
    def flush_sub():
        if cur_sub and cur_suite:
            subtotals[cur_suite].append(tuple(cur_sub))
    for ln in lines:
        m2 = h2.match(ln)
        if m2:
            flush_sub(); cur_sub = None
            cur_suite = m2.group(1).lower()
            continue
        m3 = h3.match(ln)
        if m3 and cur_suite:
            flush_sub()
            cur_sub = [m3.group(1), int(m3.group(2)), 0]
            continue
        mr = row.match(ln)
        if mr and cur_suite:
            n = int(mr.group(2))
            if cur_sub:
                cur_sub[2] += n
            else:
                row_only_sum[cur_suite] += n
    flush_sub()

    # (a) each ### subtotal must equal the sum of its file rows
    for suite in ("swift", "python"):
        for name, claimed, rowsum in subtotals[suite]:
            if claimed != rowsum:
                errors.append(f"{path}: subtotal '### {name} — {claimed}' != sum of its rows ({rowsum}) "
                              f"— update the subtotal or a row")
    # (b) the sum of a suite's contributions must equal the derived suite total
    for suite, total in (("swift", swift_total), ("python", py_total)):
        contrib = sum(c for _, c, _ in subtotals[suite]) + row_only_sum[suite]
        if contrib != total:
            errors.append(f"{path}: {suite} per-file counts sum to {contrib}, but the derived "
                          f"{suite} total is {total} — a table row/subtotal is stale")

for f in ("docs/wiki/Testing.md", "docs/wiki/Testing-zh-TW.md"):
    check_consistency(f, S, P)

if errors:
    print("\n✗ test-count sync FAILED — fix these and re-run:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
print(f"\n✓ all doc references synced to {T} ({S} Swift + {P} Python); subtotals + rows consistent.")
PY
rc=$?
[ $rc -eq 0 ] && echo "Review 'git diff', then commit:  docs: sync test counts to ${TOTAL} (${SWIFT} Swift + ${PYTHON} Python)"
exit $rc
