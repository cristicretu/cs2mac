#!/usr/bin/env bash
# Builds the gptk.dll shim and stages Apple's D3DMetal modules (from the
# Game Porting Toolkit app, never redistributed here) so Wine 11 can load them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/env.sh"
GPTK="$GPTK_ROOT"
OUT="$ROOT/build/d3dmetal"
CC="${MINGW_CC:-x86_64-w64-mingw32-gcc}"

[ -d "$GPTK/lib" ] || { echo "Game Porting Toolkit not found at $GPTK (copy redist/lib there, see README)"; exit 1; }
# only ever load Apple's own build of D3DMetal
codesign --verify --strict -R='anchor apple' "$GPTK/lib/external/libd3dshared.dylib" &&
    codesign --verify --deep --strict -R='anchor apple' "$GPTK/lib/external/D3DMetal.framework" ||
    { echo "D3DMetal in $GPTK is not signed by Apple" >&2; exit 1; }
command -v "$CC" >/dev/null || { echo "missing $CC (brew install mingw-w64)"; exit 1; }

mkdir -p "$OUT/x86_64-windows" "$OUT/x86_64-unix"
"$CC" -shared -O2 -o "$OUT/gptk.dll" "$ROOT/shim/gptk.c" "$ROOT/shim/gptk.def" -Wl,--kill-at -nostdlib -lkernel32 -e DllMain
"$CC" -O2 -o "$OUT/d3d11probe.exe" "$ROOT/shim/d3d11probe.c" -ld3d11 -ldxgi -ldxguid -municode 2>/dev/null || \
"$CC" -O2 -o "$OUT/d3d11probe.exe" "$ROOT/shim/d3d11probe.c" -ld3d11 -ldxgi -ldxguid

for dll in dxgi d3d11 d3d10 d3d12 nvapi64; do
  src="$GPTK/lib/wine/x86_64-windows/$dll.dll"
  [ -f "$src" ] || continue
  python3 "$ROOT/shim/patch_imports.py" "$src" "$OUT/x86_64-windows/$dll.dll" ntdll.dll gptk.dll
  ln -sfn "$GPTK/lib/wine/x86_64-unix/$dll.so" "$OUT/x86_64-unix/$dll.so"
done
ln -sfn "$GPTK/lib/external/D3DMetal.framework" "$OUT/x86_64-unix/D3DMetal.framework"
echo "staged D3DMetal backend in $OUT"
