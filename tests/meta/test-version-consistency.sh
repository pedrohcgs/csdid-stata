#!/usr/bin/env bash
# The version string lives in ~13 places that are otherwise hand-maintained, so
# they drift: the .ado and .sthlp headers can end up carrying two different
# dates for the same release, and nothing about the package says so. Use
# tools/release/stamp-version.py to set them together.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 tools/release/stamp-version.py --check
