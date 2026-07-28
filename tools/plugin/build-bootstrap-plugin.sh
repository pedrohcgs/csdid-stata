#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/tools/plugin/_deps"
OUTDIR="$ROOT/build"
SOURCE="$ROOT/src/plugin/csdid_bootstrap_plugin.c"
STPLUGIN_H="$DEPS/stplugin.h"
STPLUGIN_C="$DEPS/stplugin.c"

mkdir -p "$DEPS" "$OUTDIR"

fetch_dependency() {
  local url="$1"
  local destination="$2"
  local expected_sha="$3"
  if [[ ! -f "$destination" ]]; then
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

case "$target" in
  macos)
    compiler="${CC:-clang}"
    "$compiler" -std=c11 -O3 -fPIC -DSYSTEM=APPLEMAC -I"$DEPS" \
      -arch arm64 -arch x86_64 \
      -bundle "$SOURCE" "$STPLUGIN_C" -lm -o "$OUTDIR/csdid_bootstrap_macosx.plugin"
    cp "$OUTDIR/csdid_bootstrap_macosx.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  linux)
    compiler="${CC:-gcc}"
    "$compiler" -std=c11 -O3 -fPIC -DSYSTEM=OPUNIX -I"$DEPS" \
      -shared "$SOURCE" "$STPLUGIN_C" -ldl -lm -o "$OUTDIR/csdid_bootstrap_unix.plugin"
    cp "$OUTDIR/csdid_bootstrap_unix.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  windows)
    compiler="${CC:-x86_64-w64-mingw32-gcc}"
    "$compiler" -std=c11 -O3 -DSYSTEM=STWIN32 -I"$DEPS" \
      -shared -static-libgcc "$SOURCE" "$STPLUGIN_C" \
      -o "$OUTDIR/csdid_bootstrap_windows.plugin"
    cp "$OUTDIR/csdid_bootstrap_windows.plugin" "$OUTDIR/csdid_bootstrap.plugin"
    ;;
  *)
    echo "usage: $0 [auto|macos|linux|windows]" >&2
    exit 2
    ;;
esac

file "$OUTDIR/csdid_bootstrap.plugin" "$OUTDIR"/csdid_bootstrap_*.plugin
