#!/bin/bash
# Launch CS2 through the running, logged in Steam client.
# Backend comes from CS2MAC_BACKEND (vulkan | dxvk | wined3d | d3dmetal); see scripts/backend.sh.
# Extra arguments are passed to cs2.exe (e.g. +map de_dust2).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$CS2_DIR/game/bin/win64" || { echo "CS2 not installed at $CS2_DIR"; exit 1; }
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"
api=()
case "$CS2MAC_BACKEND" in
  vulkan) api=(-vulkan) ;;
  dxvk|wined3d|d3dmetal) api=() ;;
  *) echo "unknown CS2MAC_BACKEND=$CS2MAC_BACKEND"; exit 1 ;;
esac
# Default is borderless fullscreen: a window the size of the main display in points. Exclusive
# fullscreen (CS2MAC_FULLSCREEN=1) presents black with D3DMetal; CS2MAC_WINDOWED=1 gives a normal window.
if [ -z "${CS2MAC_WIDTH:-}" ] && [ "${CS2MAC_WINDOWED:-0}" != 1 ]; then
    screen="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame; f.size.width+"x"+f.size.height')"
    CS2MAC_WIDTH="${screen%x*}"; CS2MAC_HEIGHT="${screen#*x}"
fi
res=(-w "${CS2MAC_WIDTH:-1280}" -h "${CS2MAC_HEIGHT:-720}")
mode=(-windowed -noborder)
[ "${CS2MAC_WINDOWED:-0}" = 1 ] && mode=(-windowed)
[ "${CS2MAC_FULLSCREEN:-0}" = 1 ] && mode=(-fullscreen)
# Frame rate: vsync off, uncapped. With vsync on and the game below the refresh rate (~110 fps on a
# 120/144 Hz display) every frame waits for the next refresh, so fps flips between full and half
# rate. CS2MAC_VSYNC=1 turns it back on; CS2MAC_FPS_MAX=<n> caps instead (Wine's sleeps are uneven
# on macOS, so the limiter paces worse than uncapped).
fps=(+mat_vsync 0 +fps_max 0)
[ "${CS2MAC_VSYNC:-0}" = 1 ] && fps=(+mat_vsync 1 +fps_max 0)
[ -n "${CS2MAC_FPS_MAX:-}" ] && fps=(+mat_vsync 0 +fps_max "$CS2MAC_FPS_MAX")
args=("${api[@]}" -nojoy -novid -condebug +exec autoexec "${res[@]}" "${mode[@]}" "${fps[@]}" "$@")
# By default hand the launch to the running Steam client (VAC secure servers). CS2MAC_DIRECT=1 starts
# cs2.exe itself, always with -insecure so a test run can never join a VAC server.
[ "${CS2MAC_DIRECT:-0}" = 1 ] && exec "$WINE" cs2.exe -steam -insecure "${args[@]}"
# -noverifyfiles: if the running Steam does not answer, this steam.exe bootstraps a new one, and its
# file check would put the real steamwebhelper.exe back over the wrapper (seen 2026-10-16)
exec "$WINE" "$STEAM_DIR/steam.exe" -noverifyfiles -applaunch 730 "${args[@]}"
