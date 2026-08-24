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
macho_skipped=0

# 11.0 is the arm64 slice's deployment target and the higher of the two, so it
# is the ceiling the whole bundle must stay under. A bundle stamped with the
# build host's OS instead loads on nothing older than that host.
macho_min_ceiling="11.0"

version_key() {
  awk -F. '{printf "%d", $1 * 10000 + ($2 == "" ? 0 : $2) * 100 + ($3 == "" ? 0 : $3)}' <<<"$1"
}

# Architecture, linkage and deployment target of the universal bundle that
# net install actually delivers. Checked here rather than trusted from the
# build log, because the binary is committed and the log is not.
check_macho() {
  local f="$1"
  local archs slice minos lib
  local bad=0

  archs="$(lipo -archs "$f" | tr ' ' '\n' | sort | tr '\n' ' ')"
  archs="${archs% }"
  if [ "$archs" != "arm64 x86_64" ]; then
    echo "$f carries architectures [$archs], not [arm64 x86_64]" >&2
    echo "  rebuild with tools/plugin/build-bootstrap-plugin.sh macos" >&2
    bad=1
  fi

  while read -r lib; do
    case "$lib" in
      /usr/lib/*|/System/*) ;;
      *)
        echo "$f links $lib, which is outside /usr/lib and /System" >&2
        echo "  rebuild on a machine without that library on the default search path" >&2
        bad=1
        ;;
    esac
  done < <(otool -L "$f" | awk '/^\t/ {print $1}' | sort -u)

  for slice in $(lipo -archs "$f"); do
    minos="$(otool -arch "$slice" -l "$f" | awk '$1 == "minos" {print $2; exit}')"
    if [ -z "$minos" ]; then
      # A 10.x target is recorded as LC_VERSION_MIN_MACOSX, not LC_BUILD_VERSION.
      minos="$(otool -arch "$slice" -l "$f" |
        awk '/LC_VERSION_MIN_MACOSX/ {seen = 1} seen && $1 == "version" {print $2; exit}')"
    fi
    if [ -z "$minos" ]; then
      echo "$f slice $slice records no deployment target" >&2
      echo "  rebuild with tools/plugin/build-bootstrap-plugin.sh macos" >&2
      bad=1
      continue
    fi
    if [ "$(version_key "$minos")" -gt "$(version_key "$macho_min_ceiling")" ]; then
      echo "$f slice $slice requires macOS $minos, above the $macho_min_ceiling ceiling -- it will not load on older Macs" >&2
      echo "  rebuild with tools/plugin/build-bootstrap-plugin.sh macos" >&2
      bad=1
    fi
  done

  return "$bad"
}
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
  if [ "$name" = "csdid_bootstrap_macosx.plugin" ]; then
    if command -v lipo >/dev/null 2>&1 && command -v otool >/dev/null 2>&1; then
      check_macho "$ship" || fail=1
    else
      # Only a macOS host can read a Mach-O; the Linux release gates run this
      # file too, and a hard failure there would say nothing about the binary.
      echo "note: lipo and otool are unavailable, so the Mach-O checks on $ship did not run" >&2
      macho_skipped=1
    fi
  fi
done

# ---------------------------------------------------------------------------
# Provenance: the SHIPPED binary must be the build of THIS tree's C source.
# Timestamps prove nothing here; on the pinned toolchain the build is
# byte-reproducible (verified: an independent scratch-tree rebuild yields
# the identical sha256), so the check rebuilds into a scratch directory and
# compares hashes. On macOS -- the host that builds the release binary --
# the toolchain and sha-pinned SDK headers are REQUIRED and their absence
# FAILS the gate; only a non-mac host may skip, and then the final banner
# states that the comparison did not run.
# ---------------------------------------------------------------------------
# On a macOS host the prerequisites are REQUIRED: this is the platform the
# release binary is built on, so an unbuildable state is a failure, not a
# skip. Only a non-mac host (the Linux CI sweep, which cannot produce a
# Mach-O at all) may skip -- and then the success banner below must not
# claim the comparison ran.
provenance_ran=0
if command -v clang >/dev/null 2>&1 && command -v lipo >/dev/null 2>&1 \
   && [ -f tools/plugin/_deps/stplugin.h ] && [ -f tools/plugin/_deps/stplugin.c ]; then
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  if CSDID_PLUGIN_OUTDIR="$scratch" bash tools/plugin/build-bootstrap-plugin.sh macos >/dev/null 2>&1; then
    fresh="$(shasum -a 256 "$scratch/csdid_bootstrap_macosx.plugin" | cut -d" " -f1)"
    compared=0
    for placed in pkg/csdid_bootstrap_macosx.plugin src/ado/csdid_bootstrap_macosx.plugin; do
      if [ ! -f "$placed" ]; then
        # In the full source tree BOTH copies must exist; the release payload
        # strips src/ado, recognised by the absence of the C source itself.
        if [ -f src/plugin/csdid_bootstrap_plugin.c ] || [ "$placed" = "pkg/csdid_bootstrap_macosx.plugin" ]; then
          echo "$placed is missing, so its provenance cannot be compared" >&2
          fail=1
        fi
        continue
      fi
      have="$(shasum -a 256 "$placed" | cut -d" " -f1)"
      compared=$((compared + 1))
      if [ "$fresh" != "$have" ]; then
        echo "$placed (sha256 ${have:0:12}) is NOT the build of the current C source (fresh build ${fresh:0:12}); rebuild with tools/plugin/build-bootstrap-plugin.sh macos" >&2
        fail=1
      fi
    done
    if [ "$compared" -eq 0 ]; then
      echo "the scratch rebuild succeeded but NO placed binary was compared; that is not a pass" >&2
      fail=1
    fi
    if [ "$fail" -eq 0 ]; then
      provenance_ran=1
      echo "provenance: the shipped plugin is byte-identical to a fresh build of the current source"
    fi
  else
    echo "provenance check FAILED: the scratch rebuild itself failed; run tools/plugin/build-bootstrap-plugin.sh macos to see why" >&2
    fail=1
  fi
else
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "provenance check FAILED: clang/lipo or the pinned SDK headers are absent on this macOS host, where the release binary is built" >&2
    fail=1
  else
    echo "provenance check not runnable on this host (no Mach-O toolchain); the comparison DID NOT RUN"
  fi
fi

[ "$fail" -eq 0 ] || exit 1
suffix=""
[ "$provenance_ran" -eq 1 ] || suffix=" (provenance comparison did not run on this host)"
if [ "$macho_skipped" -eq 0 ]; then
  echo "shipped plugin matches the source build, guard present, universal and loadable back to macOS $macho_min_ceiling$suffix"
else
  echo "shipped plugin matches the source build, guard present (Mach-O checks not run on this host)$suffix"
fi
