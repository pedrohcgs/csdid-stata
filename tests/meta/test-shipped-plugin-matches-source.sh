#!/usr/bin/env bash
set -euo pipefail

# The plugin that net install delivers must be the one built from the C source
# in this tree.
#
# It was not. src/build.do copied the mata, the compiled library and the help
# files into pkg/ but never the plugin, so pkg/ kept a binary placed by hand on
# 30 July while the C source gained an all-zero RNG-state guard on 6 August.
# macOS installs therefore ran a plugin that accepts the one absorbing state of
# MT19937: every replication identical, standard errors silently missing, and
# no fallback to the guarded Mata path because the plugin reported success.
#
# Checked by content, not by date: a rebuild of unchanged source is not
# byte-identical, so a timestamp comparison would either pass a stale binary or
# fail a fresh one.
#
# It must also pass in the RELEASE PAYLOAD, where src/ado/'s duplicate copy is
# stripped and only pkg/ ships. The C source does ship, so the guard check
# works there; the byte comparison simply has nothing to compare against and is
# skipped rather than failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0
for name in csdid_bootstrap_macosx.plugin csdid_bootstrap_unix.plugin csdid_bootstrap_windows.plugin; do
  ship="pkg/$name"
  [ -f "$ship" ] || continue
  # src/ado/ carries a second copy in the development tree and is stripped
  # from the release payload, which ships one binary. Compare when both are
  # here; when only the shipped one is, the guard check below still applies.
  src="src/ado/$name"
  if [ -f "$src" ] && ! cmp -s "$ship" "$src"; then
    echo "$ship differs from $src -- one of them is stale" >&2
    echo "  rebuild with tools/plugin/build-bootstrap-plugin.sh and re-run src/build.do" >&2
    fail=1; continue
  fi
  # And the guard the C source carries must actually be in the binary. This is
  # the specific defect that motivated the gate, pinned so a future build that
  # silently drops it is caught rather than assumed present.
  if grep -q "absorbing state" src/plugin/csdid_bootstrap_plugin.c 2>/dev/null; then
    if [ "$(strings "$ship" | grep -c 'absorbing state')" -eq 0 ]; then
      echo "$ship does not contain the RNG absorbing-state guard that its C source defines" >&2
      fail=1
    fi
  fi
done

[ "$fail" -eq 0 ] || exit 1
echo "shipped plugin matches the source build, guard present"
