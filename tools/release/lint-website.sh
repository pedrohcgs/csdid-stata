#!/usr/bin/env bash
# Lint the public website source for content that must never be displayed
# on a public-facing page.
#
# Rule: no file-deletion commands (Stata `erase`, shell `rm`/`rmdir`/`del`)
# anywhere in website markdown. The site's code snippets are read by people
# who paste them into their own sessions; housekeeping commands that delete
# files are not content, do not earn their space, and alarm readers.
# (Removed wholesale on 2026-08-05; this gate keeps them out.)
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

echo "lint-website: OK ($(find "$SITE" -name '*.md' -not -path '*/_site/*' | wc -l | tr -d ' ') markdown files clean)"
