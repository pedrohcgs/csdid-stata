#!/usr/bin/env bash
set -euo pipefail

# NEWS.md and csdid.sthlp both reach the user -- one as a root file in the
# release payload, the other through net install -- and they are written in
# different voices at different times. That is how they came apart: the help
# said the panel-shape checks are judged on the data as `if' and `in' leave it,
# before any row is set aside for carrying a missing value, while NEWS still
# said they are judged on the estimation sample. Both read fluently and only
# one is true.
#
# No other gate compares them. check-help-surface.py reads the help alone and
# nothing reads NEWS at all.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/tools/release/check-news-help-agreement.py"
