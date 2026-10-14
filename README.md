# cs2mac

> **Hardened fork** of [PierreAndreis/cs2mac](https://github.com/PierreAndreis/cs2mac) at
> `28b3210`, reviewed line by line before use. Changes from upstream:
>
> - every file setup fetches itself is checked against a pinned SHA-256 (Homebrew and MoltenVK's
>   own `fetchDependencies` are not covered) (`scripts/setup.sh`); MoltenVK builds from
>   a clean checkout of its pinned commit
> - both halves of the single-gsbase Wine patch are installed (`ntdll.so` and `ntdll.dll`); the
>   `loader.c` half is now actually compiled (`-DCS2MAC_SINGLE_GSBASE`; upstream's `__APPLE__` guard
>   is never defined for PE code) and setup checks the built DLL for it
> - the fast UDP socket patch is removed (it skips wineserver's socket bookkeeping)
> - the `steamwebhelper.exe` wrapper is bounds-checked and built without a console window. It is
>   still needed (Steam ignores `-cef-single-process`; the flags alone leave a black window), and so
>   is `-noverifyfiles`, which stops Steam checking its own files. `CS2MAC_STEAM_WRAPPER=0` skips both
> - `./cs2mac steam` resets the prefix to stock DirectX first: D3DMetal loaded into Steam's GPU probe
>   crashes it (stock ntdll) or stalls its downloads (patched ntdll). `play` switches CS2 to D3DMetal
> - no passwords on the command line; direct `cs2.exe` launches always add `-insecure`
> - `./cs2mac stop` only kills processes in this Wine prefix (`wineserver -k`)
> - Steam's `localconfig.vdf` is backed up before the overlay is disabled
> - `./cs2mac stretch`: 4:3 stretched exclusive fullscreen. A winemac patch keeps the mode change
>   virtual, widens the pillarboxed view to the whole screen, maps the cursor per axis and hides the
>   menu bar and Dock; a small Swift helper makes the external monitor the main display while CS2 runs
> - `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0`, so ⌘-Tab out of fullscreen CS2 no longer loses input and sound
> - vsync off and fps uncapped by default (upstream forced vsync, which oscillated the frame rate)
> - benchmark, OCR, synthetic-input and workshop tooling removed
> - D3DMetal comes from Apple's own Game Porting Toolkit download (tested: 4.0 beta 3, dmg SHA-256
>   `56a7d0bd3d5375267d2d58e7f947c53fbf2fa636a824d2cd68ac2bf8c0c11e65`), not the Homebrew cask
>   (a third-party repack that strips quarantine and re-signs). Copy `redist/lib` from its
>   "Evaluation environment for Windows games" image to
>   `~/Library/Application Support/cs2mac/gptk-4.0b3/lib`; the shim build refuses anything not
>   signed by Apple. GPTK 4 resolves `__wine_unix_call_dispatcher` itself, so `gptk.dll` is now a
>   pass-through. Verified on macOS 27.0.1 / M4 Max: `d3d11probe.exe` gets a feature level 11_0
>   device on "AMD Compatibility Mode" (D3DMetal's adapter)

Run Counter-Strike 2 (the Windows build) on Apple Silicon Macs through a small, custom
translation shim: Wine 11 for the Win32 layer, Metal for the GPU, and a launcher that picks and
tunes the graphics backend.

Educational project. Valve does not ship CS2 for macOS; this is a study of how far modern
translation layers (MoltenVK, DXVK, Apple's D3DMetal) get on an M-series GPU, what breaks, and
what tuning matters. Nothing proprietary is redistributed: the scripts download Wine, MoltenVK,
DXVK and Steam from upstream, and D3DMetal comes from Apple's Game Porting Toolkit which you
install yourself.

## What works

Three backends, all playable, all benchmarked on the same map (details in `docs/RESULTS.md`):

| backend  | path                                              | 1280x720 median fps | 5th percentile |
|----------|---------------------------------------------------|--------------------:|---------------:|
| d3dmetal | D3D11 -> Apple D3DMetal -> Metal (custom shim)    | 113 | 82 |
| dxvk     | D3D11 -> DXVK 1.10 -> Vulkan -> MoltenVK -> Metal | 108 | 79 |
| vulkan   | CS2 `-vulkan` -> MoltenVK -> Metal                | 76 to 91 | 27 to 46 |

Apple M2 Max, macOS 26, everything under Rosetta 2. `d3dmetal` is the default: highest median and,
what you actually feel, the best worst-case frame times.

The custom part is getting Apple's D3DMetal (built for Apple's Wine 7/9 fork) to run inside stock
Wine 11: an import trampoline DLL, a two-file patch to Wine's ntdll (single thread-state base), and a
new `macdrv_functions` export in Wine's Mac display driver plus a one-line fix for the black window
D3DMetal otherwise gets. `docs/ARCHITECTURE.md` walks through it.

## Requirements

- Apple Silicon Mac (tested: M2 Max, 38-core GPU), macOS 26 (Tahoe) or newer
- ~45 GB free disk (CS2 is ~35 GB, the Wine prefix and toolchain ~5 GB)
- Xcode command line tools (`xcode-select --install`), Rosetta 2 (`softwareupdate --install-rosetta --agree-to-license`)
- Homebrew
- A Steam account that owns CS2 (it is free to play)
- For the `d3dmetal` backend: Apple's Game Porting Toolkit from
  [developer.apple.com/download](https://developer.apple.com/download/all/?q=game%20porting%20toolkit)
  (free Apple ID). Mount the "Evaluation environment for Windows games" dmg and copy its
  `redist/lib` to `~/Library/Application Support/cs2mac/gptk-4.0b3/lib`

## Quick start

```sh
git clone https://github.com/cristicretu/cs2mac && cd cs2mac
./cs2mac setup        # downloads Wine, MoltenVK, DXVK, Steam; builds the patched bits; creates the prefix
./cs2mac steam        # opens Steam; log in, install Counter-Strike 2
./cs2mac play         # launches CS2 on the d3dmetal backend, borderless at display size
```

For 4:3 stretched fullscreen (CS2 at 1280x960 or 1600x1200 stretched over a 16:9 monitor, menu bar
and Dock hidden, external monitor used if one is connected):

```sh
./cs2mac stretch            # 1280x960
./cs2mac stretch 1600x1200
```

Vsync is off and fps uncapped by default (`CS2MAC_VSYNC=1` or `CS2MAC_FPS_MAX=n` to change). The
first matches stutter while D3DMetal compiles shaders; play a bot match first. Wine is not banned by
VAC, but nothing guarantees this setup; your account, your risk.

`./cs2mac play dxvk 1920x1080` picks another backend and resolution. `docs/USAGE.md` has every
subcommand, `docs/TUNING.md` the knobs and what they did.

## Layout

```
cs2mac              launcher (setup | steam | play | stretch | backend | status | stop)
scripts/            setup.sh, backend.sh (switch D3D11 implementation), run-cs2.sh,
                    env.sh (paths and tunables), steam-no-overlay.py
shim/               gptk.c + gptk.def (the trampoline DLL), patch_imports.py, d3d11probe.c
patches/            wine-macos-single-gsbase.patch, wine-macos-gptk-d3dmetal.patch,
                    wine-macos-stretch-and-menubar.patch, moltenvk-null-descriptor-sets.patch
tools/              display/ (main-display helper for stretch), webhelper/ (steamwebhelper wrapper)
docs/               ARCHITECTURE.md, USAGE.md, TUNING.md, RESULTS.md
vendor/ downloads/ build/   created by setup, gitignored
```

## Legal

Wine is LGPL, MoltenVK and DXVK are Apache 2 / zlib; their sources are fetched, not vendored. The
Game Porting Toolkit is covered by Apple's license and is never copied into this repository.
Counter-Strike 2 and Steam are Valve's. Use your own account and follow Valve's terms.
