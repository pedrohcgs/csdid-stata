#!/usr/bin/env bash
set -euo pipefail

# Publish website/ to the live site.
#
# The live site is psantanna.com/csdid. GitHub Pages serves it from the USER
# site repository (pedrohcgs/pedrohcgs.github.io, CNAME psantanna.com), out of
# its csdid/ directory. Pages is deliberately disabled on csdid-stata: a
# project site there would serve at psantanna.com/csdid-stata/, a different
# address from the one every link and `baseurl: /csdid` is built for.
#
# So the path is: author markdown here -> Jekyll builds _site -> that becomes
# csdid/ in the site repository -> push.
#
# This script used to copy raw markdown to a gh-pages branch on this
# repository, which Pages does not serve. It therefore published nothing while
# looking like it published something, and the live site sat three days behind
# the source -- showing a speed range that had already been corrected here.
#
#   bash tools/release/publish-website.sh            # build, stage, show diff
#   bash tools/release/publish-website.sh --push     # and push it live
#
# Nothing is pushed without --push.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SITE_ROOT="${CSDID_SITE_ROOT:-$HOME/Documents/GitHub/pedrohcgs.github.io}"
SITE_DIR="$SITE_ROOT/csdid"
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

# ---- preconditions --------------------------------------------------------
[ -d website ] || { echo "no website/ directory" >&2; exit 1; }
[ -d "$SITE_ROOT/.git" ] || {
  echo "no site repository at $SITE_ROOT" >&2
  echo "set CSDID_SITE_ROOT to the checkout of pedrohcgs/pedrohcgs.github.io" >&2
  exit 1; }

command -v jekyll >/dev/null 2>&1 || {
  echo "jekyll is not on PATH; the site cannot be built" >&2
  echo "  gem install --user-install jekyll kramdown-parser-gfm" >&2
  echo "  and add \"\$(ruby -e 'print Gem.user_dir')/bin\" to PATH" >&2
  exit 1; }

bash tools/release/lint-website.sh

if ! git diff --quiet website || ! git diff --cached --quiet website; then
  echo "website/ has uncommitted changes; commit them first so the published" >&2
  echo "site corresponds to a recorded commit." >&2
  exit 1
fi

# Untracked files publish too, and `git diff` cannot see them. Jekyll builds
# every markdown file it finds under website/, so a working draft left beside
# the page it was drafted from -- csdid-against-the-field-new.md was, carrying
# its own front matter and an older paragraph -- becomes a second live article
# at its own address, reviewed by nobody. The check above passed on exactly
# that tree.
UNTRACKED="$(git ls-files --others --exclude-standard -- website)"
if [ -n "$UNTRACKED" ]; then
  echo "website/ has untracked files, and Jekyll would publish each of them:" >&2
  echo "$UNTRACKED" | sed 's/^/   /' >&2
  echo "Commit them or move them out of website/; the published site" >&2
  echo "corresponds to a recorded commit or it is not published." >&2
  exit 1
fi

# The published numbers must already agree with the runs that produced them.
# Publishing a page that fails its own gates is the failure this whole set of
# checks exists to prevent.
python3 tools/release/check-website-speed-tables.py
python3 tools/release/check-website-speed-prose.py
bash tests/meta/test-website-speed-claims.sh
bash tests/meta/test-reliability-tables.sh

SRC_COMMIT="$(git rev-parse --short HEAD)"

# ---- build ----------------------------------------------------------------
echo "== building website/ with Jekyll"
( cd website && jekyll build --destination _site >/dev/null )
BUILT="$(find website/_site -type f | wc -l | tr -d ' ')"
[ "$BUILT" -gt 0 ] || { echo "the build produced no files" >&2; exit 1; }
echo "   $BUILT files"

# ---- stage ----------------------------------------------------------------
if ! git -C "$SITE_ROOT" diff --quiet -- csdid || \
   ! git -C "$SITE_ROOT" diff --cached --quiet -- csdid; then
  echo "$SITE_DIR has uncommitted changes; resolve them before publishing" >&2
  exit 1
fi

mkdir -p "$SITE_DIR"
rsync -a --delete website/_site/ "$SITE_DIR/"

echo "== changes to the live site"
git -C "$SITE_ROOT" --no-pager diff --stat -- csdid | sed 's/^/   /'
CHANGED="$(git -C "$SITE_ROOT" diff --name-only -- csdid | wc -l | tr -d ' ')"
if [ "$CHANGED" = "0" ]; then
  echo "   nothing changed; the live site already matches this source"
  exit 0
fi

if [ "$PUSH" = "0" ]; then
  echo
  echo "staged in $SITE_DIR, nothing committed or pushed."
  echo "review, then re-run with --push."
  exit 0
fi

# ---- publish --------------------------------------------------------------
git -C "$SITE_ROOT" add csdid
git -C "$SITE_ROOT" commit -q -m "csdid: publish site @$SRC_COMMIT"
BRANCH="$(git -C "$SITE_ROOT" rev-parse --abbrev-ref HEAD)"
git -C "$SITE_ROOT" push origin "$BRANCH"
echo "published: $CHANGED file(s) from $SRC_COMMIT to $BRANCH"
