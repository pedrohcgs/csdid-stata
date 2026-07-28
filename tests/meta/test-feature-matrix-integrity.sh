#!/usr/bin/env bash
# The conformance ledger must be backed by artifacts that exist and evidence
# that establishes what each row claims. See tools/spec/check-matrix-integrity.py
# for the specific failures that motivated each check.
set -euo pipefail
python3 tools/spec/check-matrix-integrity.py
