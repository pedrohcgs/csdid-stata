#!/usr/bin/env bash
set -euo pipefail

# tests/ and tools/ are copied whole into the release payload, so a comment
# written for whoever was working that afternoon ends up in front of a reader
# deciding whether to trust the package. Session slugs, model and vendor names,
# and pull-request numbers all point at things that reader cannot look up, and
# a scratchpad path carries the same private framing inside a captured
# traceback or a recorded input path.
#
# The engineering rationale beside them is exactly what a stranger needs and is
# not what this removes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/spec/check-shipped-vocabulary.py"
