#!/usr/bin/env bash
# Install the git hooks that make preflight a hard requirement.
#
# Git hooks are not versioned, so this has to be run once per clone:
#     bash tools/release/install-hooks.sh
#
# The pre-push hook refuses to push unless a full preflight passed on exactly
# the code being pushed. Since Stata is licence-locked and cannot run on a
# GitHub-hosted runner, this local gate is the enforcement point.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

HOOKS="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS"

cat > "$HOOKS/pre-push" <<'HOOK'
#!/usr/bin/env bash
# Installed by tools/release/install-hooks.sh -- do not edit here; edit there.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
if [ "${SKIP_PREFLIGHT:-0}" = "1" ]; then
  echo "pre-push: SKIP_PREFLIGHT=1 set; preflight receipt NOT checked." >&2
  echo "pre-push: record this in the PR, per docs/merge-protocol.md section 5." >&2
  exit 0
fi
bash "$ROOT/tools/release/check-preflight-receipt.sh" || {
  echo "" >&2
  echo "push refused: nothing is pushed toward a PR without a green preflight." >&2
  echo "override for an emergency with:  SKIP_PREFLIGHT=1 git push" >&2
  exit 1
}
HOOK
chmod +x "$HOOKS/pre-push"

echo "installed: $HOOKS/pre-push"
echo "  it requires a full green preflight receipt matching the code being pushed."
echo "  emergency override: SKIP_PREFLIGHT=1 git push  (must be disclosed in the PR)"
