#!/usr/bin/env bash
set -euo pipefail

# Every statistical table, numerical simulation claim and hero label must
# match the complete fresh campaign. Raw files and diagnostic sources are
# authenticated before the article is compared with their structured metrics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATISTICS="tools/bench/field/results/website-statistics.json"
if [ ! -f "$STATISTICS" ]; then
  echo "missing $STATISTICS -- run the full website simulation campaign and promote its evidence" >&2
  exit 1
fi

exec python3 tools/release/check-reliability-tables.py "$STATISTICS"
