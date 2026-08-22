#!/usr/bin/env bash
# Lint the public website source for content that must never be displayed
# on a public-facing page.
#
# Rule 1: no file-deletion commands (Stata `erase`, shell `rm`/`rmdir`/`del`)
# anywhere in website markdown. The site's code snippets are read by people
# who paste them into their own sessions; housekeeping commands that delete
# files are not content, do not earn their space, and alarm readers.
#
# Rule 2: no corruption signature in the prose, delegated to
# check-website-corruption.py. A page can be damaged by a tool editing at a
# character offset computed against a version of the file it no longer has, and
# what comes out still reads like prose: every other website gate passes on it,
# because each reads only the tables and the numbers it owns and none of them
# reads the sentences.
#
# Neither rule is one the site must be written around. Rule 1 names commands
# the site has no reason to print. Rule 2 keys on the fixture ids that actually
# exist in tests/fixtures/parity/ and exempts a token that is entirely
# lowercase hex, so a git short hash in a sentence is not damage -- an earlier
# version keyed on a SHAPE, and `see commit af123b` turned it red.
#
# Usage: lint-website.sh [site-root]   (default: website/)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SITE="${1:-$ROOT/website}"

[ -d "$SITE" ] || { echo "lint-website: no such directory: $SITE" >&2; exit 2; }

PATTERN='(\berase\b|(^|[[:space:];!"])rm[[:space:]]|\brmdir\b|(^|[[:space:];!"])del[[:space:]])'

HITS="$(grep -rnE "$PATTERN" "$SITE" --include='*.md' | grep -v '/_site/' || true)"

if [ -n "$HITS" ]; then
  echo "lint-website: FAIL — file-deletion commands in public website source:" >&2
  echo "$HITS" >&2
  echo "Remove them; public pages never display housekeeping commands." >&2
  exit 1
fi

python3 "$ROOT/tools/release/check-website-corruption.py" "$SITE"

# Rule 3: no model or model-vendor names on public pages. The site speaks about
# csdid, not about how it was built; a vendor name in prose or a comment reads
# as process residue. One exact URL is exempt -- the owner's own published
# workflow page, credited in the stylesheet -- and the exemption is anchored to
# the full URL so a bare vendor name cannot ride in on it.
MODEL_PATTERN='(codex|copilot|chatgpt|claude|anthropic|gemini|openai|gpt-?[0-9]|llama-?[0-9])'
ALLOWED_URL='psantanna\.com/claude-code-my-workflow'
MHITS="$(grep -rniE "$MODEL_PATTERN" "$SITE" --include='*.md' --include='*.css' --include='*.html' \
  | grep -v '/_site/' | grep -viE "$ALLOWED_URL" || true)"

if [ -n "$MHITS" ]; then
  echo "lint-website: FAIL — model or vendor name on a public page:" >&2
  echo "$MHITS" >&2
  echo "Public pages speak about csdid, not about the tools that built it." >&2
  exit 1
fi

echo "lint-website: OK ($(find "$SITE" -name '*.md' -not -path '*/_site/*' | wc -l | tr -d ' ') markdown files clean)"


