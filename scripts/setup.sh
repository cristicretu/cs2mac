#!/usr/bin/env bash
# One-shot setup for cs2mac. Idempotent: every step checks for its output first.
#
#   setup.sh            run every step
#   setup.sh <step>...  run only the named steps (deps wine dxvk moltenvk ntdll winemac gptk gamemode prefix steam steamcfg, plus webhelper display)
#
# Nothing proprietary is redistributed: Wine, DXVK and MoltenVK are fetched from
# their upstream releases, Steam from Valve, and D3DMetal comes from Apple's
# Game Porting Toolkit which you install yourself (brew cask, needs an Apple ID).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh"
DL="$ROOT/downloads"; V="$ROOT/vendor"; LOGS="$ROOT/build/logs"
mkdir -p "$DL" "$V" "$LOGS" "$ROOT/build"

WINE_TARBALL_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.17/wine-devel-11.17-osx64.tar.xz"
WINE_SRC_URL="https://dl.winehq.org/wine/source/11.x/wine-11.17.tar.xz"
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz"
MOLTENVK_REPO="https://github.com/KhronosGroup/MoltenVK.git"
MOLTENVK_COMMIT="4aaf714aa1b3e78e26ecfcefa9c75e9a576c500b"   # 1.4.3 development head, 2026-09-04
STEAM_URL="https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe"

# SHA-256 of every download, checked before use (cached files too). Recorded 2026-10-14:
#   Wine build: matches the digest GitHub publishes for the release asset
#   Wine source: GPG signature by Alexandre Julliard (DA23 579A 74D4 AD9A F9D3  F945 CEFA C8EA AF17 519D)
#   DXVK, Steam: first download (GitHub stores no digest for that DXVK asset; Valve publishes none)
# Valve replaces SteamSetup.exe in place; on a mismatch, re-verify the new file before updating its hash.
WINE_TARBALL_SHA256="c2b3a8274dbc594deaa64e40469b607cbc4aa8ef5656dec4c5f6f3dac0da770c"
WINE_SRC_SHA256="8e752e29bba2901ad9f915139345c6ee67184b099d425704d915971ca5c055fc"
DXVK_SHA256="f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516"
STEAM_SHA256="7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb"

log() { printf '\n[setup] %s\n' "$*"; }
fetch() { # <url> <dest> <sha256>
    if [ ! -f "$2" ]; then
        curl -fL --retry 3 -o "$2.part" "$1"
        mv "$2.part" "$2"
    fi
    local got; got="$(shasum -a 256 "$2" | cut -d' ' -f1)"
    [ "$got" = "$3" ] || { echo "checksum mismatch for $2: expected $3, got $got" >&2; exit 1; }
}
x86() { arch -x86_64 "$@"; }
sign() { codesign -fs - "$1" >/dev/null 2>&1 || true; }

step_deps() {
    log "checking host dependencies"
    [ "$(uname -m)" = arm64 ] || { echo "cs2mac targets Apple Silicon"; exit 1; }
    xcode-select -p >/dev/null 2>&1 || { echo "run: xcode-select --install"; exit 1; }
    x86 /usr/bin/true 2>/dev/null || { echo "run: softwareupdate --install-rosetta --agree-to-license"; exit 1; }
    command -v brew >/dev/null || { echo "install Homebrew first"; exit 1; }
    brew list bison mingw-w64 cmake >/dev/null 2>&1 || brew install bison mingw-w64 cmake
}

step_wine() {
    log "Wine 11.17 (Gcenx build)"
    [ -x "$WINE" ] && return
    fetch "$WINE_TARBALL_URL" "$DL/wine-devel-11.17-osx64.tar.xz" "$WINE_TARBALL_SHA256"
    mkdir -p "$V/wine-11.17" && tar -xJf "$DL/wine-devel-11.17-osx64.tar.xz" -C "$V/wine-11.17"
    [ -x "$WINE" ] || { echo "unexpected Wine layout under $V/wine-11.17"; exit 1; }
}

step_dxvk() {
    log "DXVK-macOS 1.10.3 (async)"
    [ -f "$V/dxvk-macos/x64/d3d11.dll" ] && return
    fetch "$DXVK_URL" "$DL/dxvk-macos.tar.gz" "$DXVK_SHA256"
    mkdir -p "$V/dxvk-macos" && tar -xzf "$DL/dxvk-macos.tar.gz" -C "$V/dxvk-macos" --strip-components=1
}

step_moltenvk() {
    log "MoltenVK 1.4.3 from source (universal) with the null-descriptor-set patch"
    local lib="$WINE_ROOT/lib/libMoltenVK.dylib"
    [ -f "$lib.wine11" ] && return
    [ -d "$V/MoltenVK/.git" ] || git clone "$MOLTENVK_REPO" "$V/MoltenVK"
    # vendor/MoltenVK is ours: reset it to the pinned commit and wipe anything else in it
    git -C "$V/MoltenVK" checkout -q --force "$MOLTENVK_COMMIT"
    git -C "$V/MoltenVK" clean -qfdx
    git -C "$V/MoltenVK" apply --check "$ROOT/patches/moltenvk-null-descriptor-sets.patch" 2>/dev/null &&
        git -C "$V/MoltenVK" apply "$ROOT/patches/moltenvk-null-descriptor-sets.patch"
    (cd "$V/MoltenVK" && ./fetchDependencies --macos > "$LOGS/moltenvk-deps.log" 2>&1 && make macos > "$LOGS/moltenvk-make.log" 2>&1)
    cp "$lib" "$lib.wine11"
    cp "$V/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$lib"
    sign "$lib"
}

step_winesrc() {
    log "Wine 11.17 source (pristine copy in vendor/wine-src, patched build tree in vendor/wine-build)"
    [ -f "$V/wine-src/VERSION" ] || {
        fetch "$WINE_SRC_URL" "$DL/wine-11.17.tar.xz" "$WINE_SRC_SHA256"
        mkdir -p "$V/wine-src" && tar -xJf "$DL/wine-11.17.tar.xz" -C "$V/wine-src" --strip-components=1
    }
    if [ -f "$V/wine-build/config.status" ]; then
        grep -q CS2MAC_SINGLE_GSBASE "$V/wine-build/config.status" && return
        echo "vendor/wine-build was configured without CS2MAC_SINGLE_GSBASE; delete it and rerun" >&2; exit 1
    fi
    rm -rf "$V/wine-build" && cp -R "$V/wine-src" "$V/wine-build"
    (cd "$V/wine-build" &&
        patch -p1 < "$ROOT/patches/wine-macos-single-gsbase.patch" &&
        patch -p1 < "$ROOT/patches/wine-macos-gptk-d3dmetal.patch" &&
        patch -p1 < "$ROOT/patches/wine-macos-stretch-and-menubar.patch" &&
        # the PE half of the single-gsbase patch (loader.c) is compiled only with this define
        PATH="/opt/homebrew/opt/bison/bin:$PATH" CC="clang -arch x86_64" x86_64_CFLAGS="-g -O2 -DCS2MAC_SINGLE_GSBASE" \
        LDFLAGS="-L/opt/homebrew/opt/openssl@1.1/lib" CPPFLAGS="-I/opt/homebrew/opt/openssl@1.1/include" \
        x86 ./configure --enable-archs=x86_64,i386 --without-x --disable-tests --without-freetype \
            --without-gstreamer --without-sdl --without-gphoto --without-sane --without-usb --without-krb5 \
            --without-cups --without-dbus --without-gnutls --without-pcap --without-inotify --without-opencl \
            --without-oss --without-netapi > "$LOGS/wine-configure.log" 2>&1)
}

install_built() { # <path under the build tree> <path under lib/wine>; keeps the original once
    local dst="$WINE_ROOT/lib/wine/$2" orig="$ROOT/build/wine-orig/$2"
    mkdir -p "$(dirname "$orig")"
    [ -f "$orig" ] || cp "$dst" "$orig"
    cp "$V/wine-build/$1" "$dst"
    # the stock Unix libraries also search Wine's lib/ (bundled libfreetype, MoltenVK); ours must too
    case "$dst" in *.so)
        local rp; rp="$(otool -l "$dst")"
        grep -q '@loader_path/../../ ' <<<"$rp" || install_name_tool -add_rpath @loader_path/../../ "$dst" 2>/dev/null ;;
    esac
    sign "$dst"
}

build_dll() { # <dlls/ subdir>
    (cd "$V/wine-build" && PATH="/opt/homebrew/opt/bison/bin:$PATH" x86 make -j"$(sysctl -n hw.ncpu)" "dlls/$1/all" > "$LOGS/wine-make-$1.log" 2>&1)
}

step_ntdll() {
    log "ntdll (Unix and PE halves) with the single-gsbase patch D3DMetal needs"
    step_winesrc
    # A build tree from upstream cs2mac carries the fast UDP socket patch; refuse it.
    if grep -q sock_fast_path "$V/wine-build/dlls/ntdll/unix/socket.c"; then
        echo "vendor/wine-build has the fast UDP socket patch; delete vendor/wine-build and rerun" >&2; exit 1
    fi
    build_dll ntdll
    # The patch touches both halves (unix/signal_x86_64.c and loader.c); install both from one tree.
    install_built dlls/ntdll/ntdll.so x86_64-unix/ntdll.so
    install_built dlls/ntdll/x86_64-windows/ntdll.dll x86_64-windows/ntdll.dll
    # prove the loader.c half was compiled in: it is the only store to %gs:0x58 in the PE ntdll
    local dis; dis="$(x86_64-w64-mingw32-objdump -d "$WINE_ROOT/lib/wine/x86_64-windows/ntdll.dll")"
    grep -Eq 'mov +%r[a-z0-9]+,%gs:0x58' <<<"$dis" ||
        { echo "PE ntdll.dll lacks the single-gsbase TLS store; check $LOGS/wine-make-ntdll.log" >&2; exit 1; }
}

# A build tree configured before this patch existed gets it here.
stretch_patch() {
    grep -q stretch_fullscreen "$V/wine-build/dlls/winemac.drv/macdrv_cocoa.h" ||
        (cd "$V/wine-build" && patch -p1 < "$ROOT/patches/wine-macos-stretch-and-menubar.patch" >/dev/null)
}

step_winemac() {
    log "winemac.so with the GPTK macdrv_functions table, 4:3 stretch and the fullscreen menu bar fix"
    step_winesrc; stretch_patch
    build_dll winemac.drv
    install_built dlls/winemac.drv/winemac.so x86_64-unix/winemac.so
    local syms; syms="$(nm -gU "$WINE_ROOT/lib/wine/x86_64-unix/winemac.so")"
    grep -q macdrv_functions <<<"$syms" || { echo "winemac.so lacks macdrv_functions" >&2; exit 1; }
}

step_gptk() {
    log "Apple Game Porting Toolkit (D3DMetal) and the gptk.dll shim"
    if [ ! -d "$GPTK_LIB" ]; then
        echo "GPTK not found at $GPTK_ROOT. Download Game Porting Toolkit from developer.apple.com/games,"
        echo "open 'Evaluation environment for Windows games' inside it and copy its redist/lib to $GPTK_LIB"
        echo "The vulkan and dxvk backends work without it; skipping."
        return
    fi
    bash "$ROOT/scripts/build-d3dmetal-shim.sh" > "$LOGS/build-d3dmetal-shim.log" 2>&1
}

step_gamemode() {
    log "vendor/CS2.app: Wine loader in a bundle with the games category (macOS Game Mode)"
    local app="$V/CS2.app" u="$WINE_ROOT/lib/wine/x86_64-unix"
    [ -x "$app/Contents/MacOS/wine" ] && return
    step_winesrc
    (cd "$V/wine-build" && PATH="/opt/homebrew/opt/bison/bin:$PATH" x86 make loader/wine > "$LOGS/wine-make-loader.log" 2>&1)
    mkdir -p "$app/Contents/MacOS"
    cp "$ROOT/patches/CS2.app-Info.plist" "$app/Contents/Info.plist"
    cp "$V/wine-build/loader/wine" "$app/Contents/MacOS/wine"
    # the loader looks for ntdll.so next to itself
    ln -sf "$u/ntdll.so" "$app/Contents/MacOS/ntdll.so"
    sign "$app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
    # programs Wine starts through bin/wine (winedbg, services) get the same identity
    [ -L "$WINE_ROOT/bin/wine" ] || mv "$WINE_ROOT/bin/wine" "$WINE_ROOT/bin/wine.gcenx"
    ln -sfn "$app/Contents/MacOS/wine" "$WINE_ROOT/bin/wine"
}

step_webhelper() {
    # Used by ./cs2mac steam unless CS2MAC_STEAM_WRAPPER=0. Built for the GUI subsystem so Wine
    # opens no console window for it.
    log "Steam: steamwebhelper wrapper (CEF with GPU off in one process, fixes black Steam windows)"
    local cef="$STEAM_DIR/bin/cef/cef.win64" w="$ROOT/tools/webhelper"
    [ -f "$cef/steamwebhelper_real.exe" ] || mv "$cef/steamwebhelper.exe" "$cef/steamwebhelper_real.exe"
    [ "$w/steamwebhelper.exe" -nt "$w/steamwebhelper.c" ] ||
        x86_64-w64-mingw32-gcc -O2 -municode -mwindows -o "$w/steamwebhelper.exe" "$w/steamwebhelper.c"
    cmp -s "$w/steamwebhelper.exe" "$cef/steamwebhelper.exe" || cp "$w/steamwebhelper.exe" "$cef/steamwebhelper.exe"
}

step_display() {
    # Used by ./cs2mac stretch: makes the monitor the main display while CS2 runs.
    log "cs2mac-display (main display switch for ./cs2mac stretch)"
    mkdir -p "$ROOT/build"
    swiftc -O -o "$ROOT/build/cs2mac-display" "$ROOT/tools/display/cs2mac-display.swift"
}

step_steamcfg() {
    log "Steam: disable the in-game overlay for CS2 (its orphaned helper crashes under Wine)"
    for f in "$STEAM_DIR"/userdata/*/config/localconfig.vdf; do
        if [ -f "$f" ]; then python3 "$ROOT/scripts/steam-no-overlay.py" "$f"; fi
    done
}

step_prefix() {
    log "Wine prefix at $WINEPREFIX"
    # mscoree/mshtml off: no Mono/Gecko installer prompts (Steam's UI is CEF, it needs neither)
    [ -f "$WINEPREFIX/system.reg" ] ||
        WINEDEBUG=-all WINEDLLOVERRIDES="mscoree=;mshtml=" "$WINE" wineboot -u > "$LOGS/wineboot.log" 2>&1
    # Retina off: with it on, CS2's mouse coordinates don't match its window and menus can't be clicked.
    "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d n /f >/dev/null
    "$WINE" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null
    "$WINE" reg add 'HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null
    # Crashing helpers (the Steam overlay after CS2 exits) must not open Wine Debugger windows.
    "$WINE" reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null
    # 4:3 stretched for ./cs2mac stretch. Wine's emulated display modes fake CS2's mode change and
    # scale its fullscreen window to the monitor; explorer.exe builds the display list, cs2.exe changes
    # the mode (win32u reads EmulateModeset from the X11 Driver key for every driver). Not prefix-wide:
    # it also switches OpenGL to an experimental surface that crashes Steam's GPU probe. The scaling
    # keeps the aspect ratio; StretchFullscreen (patches/wine-macos-stretch-and-menubar.patch) widens
    # the pillarboxed client view to the whole window and maps the mouse back.
    for app in explorer.exe cs2.exe; do
        "$WINE" reg add "HKCU\\Software\\Wine\\AppDefaults\\$app\\X11 Driver" /v EmulateModeset /t REG_SZ /d y /f >/dev/null
    done
    "$WINE" reg add 'HKCU\Software\Wine\AppDefaults\cs2.exe\Mac Driver' /v StretchFullscreen /t REG_SZ /d y /f >/dev/null
    "$WINE" reg add 'HKCU\Software\Wine\Mac Driver' /v AllowSetGamma /t REG_DWORD /d 0 /f >/dev/null
    "$WINE" reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win10 /f >/dev/null
    "$WINESERVER" -w
}

step_steam() {
    log "Steam"
    [ -f "$STEAM_DIR/steam.exe" ] && return
    fetch "$STEAM_URL" "$DL/SteamSetup.exe" "$STEAM_SHA256"
    WINEDEBUG=-all "$WINE" "$DL/SteamSetup.exe" /S > "$LOGS/steam-install.log" 2>&1 || true
    "$WINESERVER" -w
    [ -f "$STEAM_DIR/steam.exe" ] || { echo "Steam installer did not produce steam.exe, see $LOGS/steam-install.log"; exit 1; }
}

steps=("$@"); [ ${#steps[@]} -gt 0 ] || steps=(deps wine dxvk moltenvk ntdll winemac gptk gamemode prefix steam webhelper steamcfg display)
for s in "${steps[@]}"; do "step_$s"; done
log "done. Next: ./cs2mac steam (log in, install Counter-Strike 2), then ./cs2mac play"
