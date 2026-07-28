#!/usr/bin/env bash
set -euo pipefail

report="reports/engineering-audit.md"
test -f "$report"
grep -qE 'Status: parity-verified for conformance profile v1' "$report"
grep -qE 'Architecture Audit' "$report"
grep -qE 'Dependency Audit' "$report"
grep -qE 'Performance Audit' "$report"
grep -qE 'Release Hygiene' "$report"
grep -qE 'full-JEL' "$report"
grep -qE 'needs-review' "$report"
