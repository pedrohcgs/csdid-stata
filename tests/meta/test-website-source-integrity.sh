#!/usr/bin/env bash
set -euo pipefail

# The published website source must read as prose a person wrote.
#
# The failure it prevents: an editor or an automated rewrite applies an edit at
# a character offset computed against a different revision of the page, and the
# result is a test identifier wedged inside an ordinary word -- `refF011lect`
# for `reflect` -- or a conflict marker left in the text. The speed, prose and
# reliability gates all pass on such a page, because each reads only the tables
# and numbers it owns; nothing reads the sentences.
#
# lint-website.sh carries the rules so that publish-website.sh and the release
# payload builder enforce the same ones on the same source.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/tools/release/lint-website.sh"
