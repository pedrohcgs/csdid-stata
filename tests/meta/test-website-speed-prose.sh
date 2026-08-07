#!/usr/bin/env bash
set -euo pipefail

# The tables cannot go stale -- they are generated and checked. The sentences
# around them can, and that is the likelier failure after a re-measurement.
# Every timing quoted in the speed prose must be a cell in one of that
# article's tables, and every ratio one those tables support.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/release/check-website-speed-prose.py"
