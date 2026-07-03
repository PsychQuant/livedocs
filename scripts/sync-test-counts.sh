#!/usr/bin/env bash
# Sync every doc reference to the ACTUAL test counts. Derives Swift + Python
# counts by running the suites, then rewrites the headline totals, the per-suite
# lines, and the README breakdown across all six docs. Idempotent — safe to run
# any time; running it after every test add/remove kills the recurring
# test-count-sync drift (CLAUDE.md: "This regressed twice in one day").
#
# Usage:  bash scripts/sync-test-counts.sh   (then review `git diff` and commit)
#
# Post-merge note: after a batch that changed test counts across multiple
# branches (e.g. a Swift cluster + an independent Python change) lands on the
# default branch, the shared headline-total lines can conflict at merge and each
# per-suite line is only half-right until reconciled — run this once to derive
# the real totals and rewrite them consistently.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SWIFT=$(swift test 2>&1 | grep -oE 'Executed [0-9]+ tests, with' | grep -oE '[0-9]+' | sort -n | tail -1)
PYTHON=$(python3 -m pytest evals/look-up/tests/ --co -q 2>&1 | grep -c '::')
TOTAL=$(( SWIFT + PYTHON ))
[ "${SWIFT:-0}" -gt 0 ] && [ "${PYTHON:-0}" -gt 0 ] || { echo "refusing: derived Swift=${SWIFT:-} Python=${PYTHON:-} (a suite failed to run?)" >&2; exit 1; }
echo "Derived: Swift=$SWIFT  Python=$PYTHON  Total=$TOTAL"

SWIFT="$SWIFT" PYTHON="$PYTHON" TOTAL="$TOTAL" python3 - <<'PY'
import os, re
S, P, T = os.environ["SWIFT"], os.environ["PYTHON"], os.environ["TOTAL"]

# (path, [(regex, replacement)]) — regexes match ANY current digits so the sync
# is idempotent regardless of the pre-run state. \g<1>/\g<2> keep surrounding text.
# When adding a NEW doc reference to a test count anywhere, add its phrasing here
# too (per CLAUDE.md test-count-sync discipline) so this script stays complete.
edits = {
  "docs/wiki/Testing.md": [
    (r"\*\*\d+ tests, all green\*\*", f"**{T} tests, all green**"),
    (r"(swift test\s+#\s*)\d+( Swift tests)", rf"\g<1>{S}\g<2>"),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( Python eval tests)", rf"\g<1>{P}\g<2>"),
    (r"## Swift — \d+ tests", f"## Swift — {S} tests"),
    (r"## Python — \d+ tests", f"## Python — {P} tests"),
    (r"(grew 72 → )\d+( Swift tests)", rf"\g<1>{S}\g<2>"),
    (r"(0 → )\d+( for the Python evals)", rf"\g<1>{P}\g<2>"),
  ],
  "docs/wiki/Testing-zh-TW.md": [
    (r"\*\*\d+ 個 test,全綠\*\*", f"**{T} 個 test,全綠**"),
    (r"(swift test\s+#\s*)\d+( 個 Swift test)", rf"\g<1>{S}\g<2>"),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( 個 Python eval test)", rf"\g<1>{P}\g<2>"),
    (r"## Swift — \d+ 個 test", f"## Swift — {S} 個 test"),
    (r"## Python — \d+ 個 test", f"## Python — {P} 個 test"),
    (r"(從 72 → )\d+", rf"\g<1>{S}"),
    (r"(Python eval 從 0 → )\d+", rf"\g<1>{P}"),
  ],
  "docs/wiki/Home.md": [
    (r"\(\d+ tests\) and what each covers", f"({T} tests) and what each covers"),
  ],
  "docs/wiki/Home-zh-TW.md": [
    (r"（\d+ 個 test）", f"（{T} 個 test）"),
  ],
  "README.md": [
    (r"suite breakdown \(\d+ tests: \d+ Swift \+ \d+ Python\)",
     f"suite breakdown ({T} tests: {S} Swift + {P} Python)"),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( harness unit tests)", rf"\g<1>{P}\g<2>"),
  ],
  "CLAUDE.md": [
    (r"(swift test\s+#\s*)\d+( Swift tests \(no network\))", rf"\g<1>{S}\g<2>"),
    (r"(pytest evals/look-up/tests/\s+#\s*)\d+( Python tests \(no API calls\))", rf"\g<1>{P}\g<2>"),
  ],
}

for path, pairs in edits.items():
    if not os.path.exists(path):
        print(f"  skip (absent): {path}"); continue
    s = open(path).read(); hits = 0
    for rx, rep in pairs:
        s, n = re.subn(rx, rep, s); hits += n
    open(path, "w").write(s)
    print(f"  {path}: {hits} reference(s) synced")
PY
echo "Done. Review 'git diff', then commit:  docs: sync test counts to ${TOTAL} (${SWIFT} Swift + ${PYTHON} Python)"
