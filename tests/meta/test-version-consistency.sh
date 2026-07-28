#!/usr/bin/env bash
# The version string lived in ~13 hand-maintained places and had already drifted:
# the .ado and .sthlp headers carried two different dates (07jul2026 / 09jul2026)
# for the same release. Use tools/release/stamp-version.py to set them together.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 tools/release/stamp-version.py --check
