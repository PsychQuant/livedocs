#!/bin/bash
# Mirror docs/wiki/*.md -> the GitHub wiki, 1:1.
# docs/wiki/ is the source of truth (version-controlled, PR-reviewed); the wiki is a
# generated copy. Run this after editing anything under docs/wiki/.
set -euo pipefail
REPO="PsychQuant/livedocs"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/docs/wiki"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone -q "https://github.com/${REPO}.wiki.git" "$TMP" 2>/dev/null || {
  git init -q "$TMP"
  git -C "$TMP" remote add origin "https://github.com/${REPO}.wiki.git"
}

# Delete wiki content pages absent from docs/wiki (keep special _Sidebar/_Footer), then copy.
for f in "$TMP"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in _*) continue;; esac
  [ -e "$SRC/$base" ] || rm -f "$f"
done
cp "$SRC"/*.md "$TMP"/

cd "$TMP"
git add -A
if git diff --cached --quiet; then
  echo "wiki already up to date"
else
  git commit -q -m "sync wiki from docs/wiki/ (source of truth)"
  git push -q origin HEAD
  echo "wiki synced: $(ls "$SRC"/*.md | wc -l | tr -d ' ') pages"
fi
