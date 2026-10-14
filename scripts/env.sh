#!/usr/bin/env bash
# Shared environment for cs2mac. Source this, don't execute it.
# Everything here is tunable; see docs/TUNING.md for what each knob does.

CS2MAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
CS2MAC_HOME="${CS2MAC_HOME:-$HOME/Library/Application Support/cs2mac}"
export WINEPREFIX="${WINEPREFIX:-$CS2MAC_HOME/prefix}"

# Wine 11.17 (gcenx build, wow64, bundles MoltenVK) unpacked by scripts/setup.sh
export WINE_ROOT="${WINE_ROOT:-$CS2MAC_ROOT/vendor/wine-11.17/Wine Devel.app/Contents/Resources/wine}"
# vendor/CS2.app wraps the Wine loader in a bundle that declares the games category, so macOS
# turns on Game Mode for fullscreen CS2 (setup.sh step "gamemode"). Falls back to the stock loader.
if [ -x "$CS2MAC_ROOT/vendor/CS2.app/Contents/MacOS/wine" ]; then
    export WINE="${WINE:-$CS2MAC_ROOT/vendor/CS2.app/Contents/MacOS/wine}"
else
    export WINE="${WINE:-$WINE_ROOT/bin/wine}"
fi
export WINESERVER="${WINESERVER:-$WINE_ROOT/bin/wineserver}"

# Apple Game Porting Toolkit (only needed for the d3dmetal backend)
# Apple's redist/lib, copied out of "Evaluation environment for Windows games" in the Game Porting
# Toolkit download from developer.apple.com (Apple-signed; see README). Not the Homebrew cask, which
# installs a third-party repack and re-signs it.
export GPTK_ROOT="${GPTK_ROOT:-$CS2MAC_HOME/gptk-4.0b3}"
export GPTK_LIB="$GPTK_ROOT/lib"

export WINEDEBUG="${WINEDEBUG:--all}"
# CS2 is an SDL app; in exclusive fullscreen (./cs2mac stretch) SDL minimizes it when it loses focus,
# and Wine never gives focus back to a minimized window, so after cmd-tab the game got no keyboard
# or sound. CS2 inherits this from Steam, so it has to be set before ./cs2mac steam.
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS="${SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS:-0}"
export WINEESYNC="${WINEESYNC:-1}"
export WINEMSYNC="${WINEMSYNC:-1}"

# Backend selection: vulkan (CS2 -vulkan -> MoltenVK), dxvk, d3dmetal
export CS2MAC_BACKEND="${CS2MAC_BACKEND:-vulkan}"

STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
CS2_DIR="$STEAM_DIR/steamapps/common/Counter-Strike Global Offensive"
