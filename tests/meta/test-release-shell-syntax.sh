#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# bash -n accepts one script; additional paths are its positional arguments.
# Check each file separately so a later filename cannot escape parsing.
count=0
for script in tools/release/*.sh tools/plugin/*.sh; do
    bash -n "$script"
    count=$((count + 1))
done
echo "release shell syntax: $count scripts parsed"
