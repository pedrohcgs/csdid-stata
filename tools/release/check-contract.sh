#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -f tools/validate-contract.py ]]; then
    exec python3 tools/validate-contract.py
fi
if [[ -f tools/release/build-release-payload.sh ]]; then
    echo "missing tools/validate-contract.py in the source that requires it" >&2
    exit 1
fi
echo "contract schema: not included in this source distribution; package checks still run"
