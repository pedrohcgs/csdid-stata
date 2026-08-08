#!/usr/bin/env bash
# Publish website/ to the gh-pages branch.
#
# GitHub Pages can only serve from the repository root or /docs, and /docs here
# holds 34 engineering documents that are not user-facing. So the site is
# authored in website/ on the working branch and published to an orphan
# gh-pages branch, which keeps main clean and keeps engineering docs out of the
# public site.
#
# One-time setup after the first run: repository Settings -> Pages -> Source ->
# Deploy from a branch -> gh-pages / (root).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

[ -d website ] || { echo "no website/ directory" >&2; exit 1; }
bash tools/release/lint-website.sh
if ! git diff --quiet website || ! git diff --cached --quiet website; then
  echo "website/ has uncommitted changes; commit them first so the published" >&2
  echo "site corresponds to a recorded commit." >&2
  exit 1
fi

SRC_COMMIT="$(git rev-parse --short HEAD)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R website/. "$TMP/"
touch "$TMP/.nojekyll.disabled"   # placeholder: Jekyll IS wanted, see _config.yml
rm -f "$TMP/.nojekyll.disabled"

git worktree add --detach "$TMP/wt" >/dev/null 2>&1 || true
if git show-ref --verify --quiet refs/heads/gh-pages; then
  git -C "$TMP/wt" checkout gh-pages
else
  git -C "$TMP/wt" checkout --orphan gh-pages
  git -C "$TMP/wt" rm -rf . >/dev/null 2>&1 || true
fi
find "$TMP/wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R website/. "$TMP/wt/"
git -C "$TMP/wt" add -A
git -C "$TMP/wt" commit -q -m "site: publish from $SRC_COMMIT" || echo "  nothing to publish"
git worktree remove --force "$TMP/wt"
echo "gh-pages updated from $SRC_COMMIT. Push with: git push origin gh-pages"
