#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/tools/plugin/_deps"
OUTDIR="$ROOT/build"
SOURCE="$ROOT/src/plugin/csdid_bootstrap_plugin.c"
STPLUGIN_H="$DEPS/stplugin.h"
STPLUGIN_C="$DEPS/stplugin.c"

mkdir -p "$DEPS" "$OUTDIR"

require_tool() {
  local tool="$1"
  local remedy="$2"
  command -v "$tool" >/dev/null 2>&1 && return 0
  echo "$tool not found; $remedy" >&2
  exit 1
}

fetch_dependency() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  if [[ ! -f "$destination" ]]; then
    # Probed only on the download path: a tree that already carries the pinned
    # headers builds offline, and demanding curl there would be a false stop.
    require_tool curl "install curl, or place stplugin.h and stplugin.c from https://www.stata.com/plugins/ in $DEPS"
    curl -fsSL "$url" -o "$destination"
  fi
  local actual_sha
  actual_sha="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "checksum mismatch for $destination" >&2
    exit 1
  fi
}

fetch_dependency \
  "https://www.stata.com/plugins/stplugin.h" \
  "$STPLUGIN_H" \
  "0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b"
fetch_dependency \
  "https://www.stata.com/plugins/stplugin.c" \
  "$STPLUGIN_C" \
  "ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d"

target="${1:-auto}"
if [[ "$target" == "auto" ]]; then
  case "$(uname -s)" in
    Darwin) target="macos" ;;
    Linux) target="linux" ;;
    MINGW*|MSYS*|CYGWIN*) target="windows" ;;
    *) echo "unsupported build host" >&2; exit 1 ;;
  esac
fi

# -ffp-contract=off on every target, not as a style choice: the multiplier
# accumulation `sums_a[a] += sign * row[a]' is contractible, so at -O3 with
# clang's default the arm64 slice fuses it into fmadd (one rounding) while
# baseline x86_64, which has no FMA, does not. One universal binary would then
# answer the same seeded bootstrap two ways on the two Macs it ships to.
#
# -Werror because this binary ships: the warning channel has no other reader.
CFLAGS_COMMON=(-std=c11 -O3 -ffp-contract=off -Wall -Wextra -Werror)

case "$target" in
  macos)
    compiler="${CC:-clang}"
    require_tool "$compiler" "install the Xcode command line tools with: xcode-select --install"
    require_tool lipo "install the Xcode command line tools with: xcode-select --install"
    # Two compiles, then lipo -- not one invocation with two -arch flags. A
    # single invocation carries one deployment target for both slices, and
    # with none given clang stamps the build host's OS into LC_BUILD_VERSION,
    # which dyld then refuses on every older Mac.
    "$compiler" "${CFLAGS_COMMON[@]}" -fPIC -DSYSTEM=APPLEMAC -I"$DEPS" \
      -target x86_64-apple-macos10.12 \
      -bundle "$SOURCE" "$STPLUGIN_C" -lm -o "$OUTDIR/csdid_bootstrap_macosx.x86_64"
    "$compiler" "${CFLAGS_COMMON[@]}" -fPIC -DSYSTEM=APPLEMAC -I"$DEPS" \
      -target arm64-apple-macos11 \
      -bundle "$SOURCE" "$STPLUGIN_C" -lm -o "$OUTDIR/csdid_bootstrap_macosx.arm64"
    lipo -create \
      "$OUTDIR/csdid_bootstrap_macosx.x86_64" \
      "$OUTDIR/csdid_bootstrap_macosx.arm64" \
      -output "$OUTDIR/csdid_bootstrap_macosx.plugin"
    rm -f "$OUTDIR/csdid_bootstrap_macosx.x86_64" "$OUTDIR/csdid_bootstrap_macosx.arm64"
    cp "$OUTDIR/csdid_bootstrap_macosx.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  linux)
    compiler="${CC:-gcc}"
    require_tool "$compiler" "install a C compiler (gcc or clang), or set CC to one"
    "$compiler" "${CFLAGS_COMMON[@]}" -fPIC -DSYSTEM=OPUNIX -I"$DEPS" \
      -shared "$SOURCE" "$STPLUGIN_C" -ldl -lm -o "$OUTDIR/csdid_bootstrap_unix.plugin"
    cp "$OUTDIR/csdid_bootstrap_unix.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  windows)
    compiler="${CC:-x86_64-w64-mingw32-gcc}"
    require_tool "$compiler" "install the mingw-w64 cross compiler, or set CC to one"
    "$compiler" "${CFLAGS_COMMON[@]}" -DSYSTEM=STWIN32 -I"$DEPS" \
      -shared -static-libgcc "$SOURCE" "$STPLUGIN_C" \
      -o "$OUTDIR/csdid_bootstrap_windows.plugin"
    cp "$OUTDIR/csdid_bootstrap_windows.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  *)
    echo "usage: $0 [auto|macos|linux|windows]" >&2
    exit 2
    ;;
esac

# Place the freshly built binary where the package actually ships it.
#
# src/build.do copies the mata, the compiled library and the help files into
# pkg/ and not the plugin. Left to that, pkg/ keeps whatever binary was put
# there by hand -- an old one, missing the all-zero RNG-state guard, say --
# and net install ships pkg/.
#
# Done here rather than in build.do because Stata's `copy` does not preserve
# the executable bit, and silently demoting the shipped plugin to 644 is its
# own defect.
for placed in "$OUTDIR"/csdid_bootstrap_*.plugin; do
  [ -e "$placed" ] || continue
  base="$(basename "$placed")"
  [ "$base" = "csdid_bootstrap.plugin" ] && continue
  for dest in "$ROOT/src/ado" "$ROOT/pkg"; do
    [ -d "$dest" ] || continue
    cp -p "$placed" "$dest/$base"
    chmod 755 "$dest/$base"
    echo "placed $base in ${dest#$ROOT/}"
  done
done


file "$OUTDIR/csdid_bootstrap.plugin" "$OUTDIR"/csdid_bootstrap_*.plugin
