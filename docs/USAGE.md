# Usage

Everything goes through the `./cs2mac` launcher. Every subcommand is a thin wrapper over a
script in `scripts/`, so you can also call those directly.

## 1. Setup

```sh
./cs2mac setup
```

Runs `scripts/setup.sh`, which is idempotent (re-run it after a failure, it skips what is done):

| step       | what it does                                                                                     |
|------------|--------------------------------------------------------------------------------------------------|
| deps       | checks Apple Silicon, Xcode CLT, Rosetta 2, Homebrew; installs `bison mingw-w64 cmake`           |
| wine       | downloads Gcenx's Wine 11.17 build into `vendor/wine-11.17`                                      |
| dxvk       | downloads DXVK-macOS 1.10.3 (async) into `vendor/dxvk-macos`                                     |
| moltenvk   | clones MoltenVK, applies `patches/moltenvk-null-descriptor-sets.patch`, builds it universal, swaps it into Wine |
| ntdll      | downloads the Wine 11.17 source, applies `patches/wine-macos-single-gsbase.patch`, builds and installs `ntdll.so` and `ntdll.dll` |
| winemac    | applies `patches/wine-macos-gptk-d3dmetal.patch`, builds and installs `winemac.so`               |
| gptk       | builds the `gptk.dll` shim and stages Apple's D3DMetal (skipped if the Game Porting Toolkit is not installed) |
| prefix     | creates the Wine prefix in `~/Library/Application Support/cs2mac/prefix` and sets the registry knobs |
| steam      | downloads and silently installs the Windows Steam client into the prefix                         |

Run a single step with `./cs2mac setup <step>`. The Wine build steps take 10 to 20 minutes on an
M2 Max; MoltenVK about 5.

For the `d3dmetal` backend you need Apple's Game Porting Toolkit. It is not redistributable, so
install it yourself before running setup (or run `./cs2mac setup gptk` afterwards):

```sh
brew install --cask gcenx/wine/game-porting-toolkit
```

The cask asks for the "Game Porting Toolkit" download from developer.apple.com in `~/Downloads`.
Only the `D3DMetal.framework` and `libd3dshared.dylib` plus the `d3d11.dll`/`dxgi.dll` PE files
from it are used; the toolkit's own Wine is never run.

## 2. Steam

```sh
./cs2mac steam
```

Starts Steam inside the prefix. Log in, then install Counter-Strike 2 from the library (about
35 GB). Steam's UI is Chromium; `./cs2mac steam` runs it through the `steamwebhelper.exe` wrapper
(GPU off, single process) because Steam ignores `-cef-single-process` and the window otherwise stays
black. It also switches the prefix back to stock DirectX first, since Steam must not load D3DMetal.
Always log in through the Steam window; never pass a password on the command line.

Keep Steam running while you play; CS2 refuses to start without it.
`play` starts CS2 through Steam so VAC secure servers work. `CS2MAC_DIRECT=1` launches `cs2.exe`
directly and always adds `-insecure`, for offline testing only.

## 3. Play

`stretch` uses the external monitor (`CS2MAC_DISPLAY=builtin` for the laptop screen), makes it the
main display and restores mode and arrangement when CS2 exits. The stretching itself is done by the
monitor: set its aspect ratio option to full screen, or it shows 4:3 with black bars. Vsync is off
by default (`CS2MAC_VSYNC=1` turns it on): below the refresh rate it makes fps flip between full and
half rate.

```sh
./cs2mac play                      # d3dmetal, borderless at the main display size
./cs2mac play dxvk 1920x1080       # borderless window of that size
./cs2mac play vulkan 1280x720 +map de_dust2
CS2MAC_WINDOWED=1 ./cs2mac play d3dmetal 1280x720   # normal window with a title bar
./cs2mac stretch                   # 4:3 stretched: monitor switched to 1280x960 while CS2 runs
./cs2mac stretch 1600x1200         # another real mode of the monitor (the error lists them)
```

The first argument is the backend (`d3dmetal`, `dxvk`, `vulkan`, `wined3d`), the second the
resolution, anything after that goes to `cs2.exe`. Switching backends rewrites a few files in the
Wine install and the prefix (see `scripts/backend.sh status`); it is safe to do while Steam runs,
but not while CS2 runs.

## 4. Game Mode, crash windows, black Steam

- **Black Steam windows** come from Steam's embedded Chromium (CEF 126) under Wine on macOS. Setup
  installs a small `steamwebhelper.exe` wrapper (`tools/webhelper`) that runs the real helper with
  `--disable-gpu --single-process`, the approach from
  [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine). This fork passes the same flags
  to Steam directly and only uses the wrapper with `CS2MAC_STEAM_WRAPPER=1` (which also needs
  `-noverifyfiles`, so Steam stops checking its own files).

- **Game Mode** comes from the `vendor/CS2.app` bundle. Don't use `CS2MAC_FULLSCREEN=1` (exclusive
  fullscreen), it renders black with D3DMetal; the default borderless mode is the way to play. It needs the `gamemode` setup step (done by a full `setup.sh`).
- **"Program error" / Wine Debugger windows** came from the Steam overlay helper crashing after CS2
  quits. Setup disables the overlay for CS2 (`setup.sh steamcfg`, run with Steam stopped) and turns
  off Wine's crash dialog; `./cs2mac stop` also kills the helper.

## 5. Other

```sh
./cs2mac status        # what is installed, what backend the prefix is on
./cs2mac backend dxvk  # switch without launching
./cs2mac stop          # kill CS2, Steam and the wineserver
```

Logs land in `build/logs/`. To debug the D3DMetal path, run with `WINEDEBUG=+gptk` (the shim's
own channel) or `CS2MAC_GPTK_DEBUG=1` (dumps the Cocoa view and layer tree of the game window).
