#!/usr/bin/env bash
set -euo pipefail

# Every speed table on the website must be exactly what the committed benchmark
# results produce. The tables are generated; this re-derives them and compares.
#
# The failure it prevents: a benchmark is re-run and only some tables are
# refreshed, or a table is edited by hand, and the site then reports numbers no
# run ever produced. Nothing about a markdown table announces it has gone stale.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/release/check-website-speed-tables.py"
