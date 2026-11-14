# Galaxy DeX on PC — design spec

Goal: one-liner install on Debian Linux (x86_64), macOS (Apple Silicon, Intel best-effort) and
Windows 10/11 (x64, ARM64 best-effort) that runs **Samsung DeX (One UI 8+) inside a resizable
window on the PC**, over USB or Wi-Fi, using scrcpy's virtual display (`--new-display`) with
`--flex-display` (virtual display follows window size → DeX windows can be resized / multitasked
freely).

Hard constraints

- **No admin / root / sudo, ever.** School PCs are locked down and wiped on reboot. Everything
  goes in the user's home / `%LOCALAPPDATA%`. Re-running the one-liner must be fast and idempotent.
- No package manager dependency (no apt, brew, winget). Use the official scrcpy release archives,
  which bundle `adb`.
- All user-facing text in **English**. Short, friendly, actionable. Colors only when stdout is a TTY.
- Repo slug lives in one variable: `DEX_REPO` (default `ErenKaynak/dex-script`, branch `main`).
  Raw base: `https://raw.githubusercontent.com/$DEX_REPO/main`.

## scrcpy

- Pinned version `5.0.1` (override with env `DEX_SCRCPY_VERSION`). Do NOT query the GitHub API
  (school NAT shares one IP → API rate limit). Download URLs:
  `https://github.com/Genymobile/scrcpy/releases/download/v$V/<asset>`
  - Linux x86_64: `scrcpy-linux-x86_64-v$V.tar.gz` (top dir `scrcpy-linux-x86_64-v$V/`)
  - macOS arm64: `scrcpy-macos-aarch64-v$V.tar.gz`; macOS x86_64: `scrcpy-macos-x86_64-v$V.tar.gz`
  - Windows x64: `scrcpy-win64-v$V.zip`; ARM64: `scrcpy-winarm64-v$V.zip`
  - Checksums: `SHA256SUMS.txt` in the same release (format `<sha256>  <filename>`). Verify; abort on
    mismatch. (Linux: `sha256sum`, mac: `shasum -a 256`, Windows: `Get-FileHash`.)
- Each archive contains `scrcpy`(.exe), `adb`(.exe), `scrcpy-server`, `scrcpy.png` (icon) etc.
- Skip download if the installed version already matches.

## Install layout

| | Linux / macOS | Windows |
|---|---|---|
| root | `~/.local/share/dex` | `%LOCALAPPDATA%\dex` |
| scrcpy | `<root>/scrcpy/` (flattened, version in `<root>/scrcpy/VERSION`) | same |
| CLI | `~/.local/bin/dex` (bash) | `<root>\bin\dex.ps1` + `<root>\bin\dex.cmd` shim |
| config | `~/.config/dex/config` | `%APPDATA%\dex\config` |
| PATH | append `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`, `~/.zshrc`, `~/.profile` if missing (marker comment `# dex`) | add `<root>\bin` to **user** PATH (HKCU) and current session |
| launcher | Linux: `~/.local/share/applications/galaxy-dex.desktop` (Terminal=true, Exec=dex, Icon=scrcpy.png). macOS: `~/Applications/Galaxy DeX.command` (runs `dex`, chmod +x) | Start Menu + Desktop shortcut "Galaxy DeX" → `dex.cmd` (WScript.Shell COM) |

`dex.cmd` runs `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dex.ps1" %*`.

Installer must support **local source** for testing: if env `DEX_SOURCE_DIR` is set, copy the CLI
from `$DEX_SOURCE_DIR/bin/` instead of downloading from the raw URL. Env `DEX_NO_SHORTCUT=1` skips
launcher creation (CI). Env `DEX_HOME` overrides the root (tests).

Installer ends by printing: installed version, how to start (`dex`), and the first-time phone
checklist (below). Windows PS 5.1: force TLS 1.2; use `$ProgressPreference='SilentlyContinue'` for
fast `Invoke-WebRequest`.

## CLI: `dex [command] [options]`

`dex` with no command on an interactive terminal opens the menu (TUI, below). Non-interactive
(no TTY, or env `DEX_NO_TUI=1`) it behaves like `dex code`, so scripts and CI keep working.

Commands

| command | does |
|---|---|
| `dex` / `dex code` | start DeX, profile **code** (default) |
| `dex school` | profile **school** |
| `dex movie` | profile **movie** + print the DRM note |
| `dex mirror` | plain phone-screen mirror (no virtual display) for apps that misbehave in DeX |
| `dex pair` | wireless pairing without a cable (Android "Pair device with pairing code") |
| `dex connect [ip:port]` | connect over Wi-Fi (no arg → discover via mDNS, else last saved endpoint, else prompt) |
| `dex wifi` | USB plugged → `adb tcpip 5555`, read phone Wi-Fi IP (`adb shell ip -f inet addr show wlan0`), connect, save endpoint; tell user to unplug (survives until phone reboot) |
| `dex wake` | `adb shell input -d 0 keyevent KEYCODE_WAKEUP` (+ plain `KEYCODE_WAKEUP`); recovers a frozen DeX window after the phone dozed |
| `dex keyboard` | open phone's Physical keyboard settings (`adb shell am start -a android.settings.HARD_KEYBOARD_SETTINGS`) and tell user to pick **Turkish Q** |
| `dex doctor` | versions (scrcpy/adb), `adb devices -l`, phone model, Android SDK (`getprop ro.build.version.sdk`), One UI (`getprop ro.build.version.oneui`, e.g. 90000 → 9.0), warn if One UI < 8 (DeX on virtual display needs 8+) |
| `dex update` | re-run the installer from the raw URL (same one-liner) |
| `dex uninstall` | remove root dir, CLI, launchers, PATH lines; keep nothing |
| `dex help` / `-h` | usage |

Options (any start command): `--res WxH` (initial size; default = 80% of primary screen if
detectable, else 1600x900; with `--fullscreen` 100% / 1920x1080), `--dpi N`, `--usb`, `--wifi`,
`--screen on|dim|off` (`--screen-off` = off), `--fullscreen`, `--no-freeform`, `--` then extra raw
scrcpy args.

### Interactive menu (TUI)

Boxed menu (UTF-8 box drawing when the locale / console is UTF-8, ASCII otherwise), single-key
selection, loops until `q`:

- header: `Galaxy DeX` + scrcpy version; status line with phone model, One UI version and
  transport (`via USB` / `via Wi-Fi`), or "no phone found", "UNAUTHORIZED", udev hint; settings
  line (`phone on|dim|off`, `window|fullscreen`, `res @ dpi`).
- `Enter`/`1` Code, `2` School, `3` Movie, `4` Mirror, `p` Pair, `c` Connect, `w` Wi-Fi, `k`
  Keyboard, `s` cycle `DEX_SCREEN` on → dim → off, `f` toggle `DEX_FULLSCREEN`, `r` prompt
  `DEX_RES` / `DEX_DPI`, `d` Doctor, `x` Wake, `u` Update, `h` help, `q`/Esc quit.
- After an action: "Press any key to return to the menu". Errors (no device etc.) are shown in
  the menu instead of exiting.

### Start sequence (DeX profiles)

1. Select device, resolve options.
2. **Wake**: `dumpsys power` → if `mWakefulness=Asleep|Dozing` inject `KEYCODE_WAKEUP` and wait 1 s
   (scrcpy 5.0.1 never powers on the device for a new virtual display; a dozing Galaxy renders
   nothing). `dumpsys window policy` → KeyguardServiceDelegate `showing=true` → warn "unlock".
3. **Freeform prerequisite** (unless `--no-freeform` / `DEX_FREEFORM=0` / mirror): if
   `settings get global enable_freeform_support` ≠ 1, set it to 1; restore the original value
   (`null` → `settings delete`) after scrcpy exits.
4. **Screen mode**: `dim` → save `screen_brightness` + `screen_brightness_mode`, set mode 0 and
   brightness 0, restore after exit (also on Ctrl+C). `off` → scrcpy `--turn-screen-off`.
5. Run scrcpy with stdout+stderr streamed to the console and watched line by line. On
   `New display: WxH/DPI (id=N)` run `adb shell wm set-display-windowing-mode -d N 5`
   (5 = WINDOWING_MODE_FREEFORM). One UI 8.5/9 (Android 16 QPR2+) no longer activates desktop
   windowing on app-created virtual displays (scrcpy issue #6143): DeX starts but every app is
   fullscreen and immovable. The per-display persisted windowing mode is checked before all
   desktop-mode heuristics in `DisplayWindowSettings.getWindowingModeLocked()`, so forcing it
   gives movable, resizable windows. On One UI 8.0 the command does not exist (ignored; freeform
   already works). scrcpy 5.x keeps the same virtual display across resizes and capture resets,
   so the id is stable; the watcher re-applies anyway if the line repeats.
6. Return scrcpy's exit code (0 closed, 2 device disconnected); restore phone settings.

### Device selection (start commands)

1. `--usb` or a USB device present in `adb devices` (serial without `:`) → use `-s <serial>`.
2. Else `--wifi`/no USB: if an already-connected TCP device exists → use it. Else try `adb mdns
   services` for `_adb-tls-connect._tcp` → `adb connect`; else last saved endpoint
   (`DEX_LAST_ENDPOINT` in config) → `adb connect`.
3. Still nothing → explain three options: plug USB cable, `dex pair`, `dex wifi`.
4. Several devices → pick the first USB one, else first TCP one, and say which.
   Device in state `unauthorized` → tell user to accept the "Allow USB debugging" prompt on phone.

### `dex pair` flow (school PCs: run every boot, no cable)

Print steps: Phone → Settings → Developer options → **Wireless debugging** ON → **Pair device with
pairing code**. Prompt for `IP:port` shown in the pairing dialog and the 6-digit code →
`adb pair ip:port code`. Then the *connect* port (different from the pairing port; shown on the
Wireless debugging main screen as "IP address & Port"): try mDNS discovery first, else prompt for
it → `adb connect`, save endpoint to config. On failure print hints: same Wi-Fi network; school Wi-Fi
may isolate clients → use PC hotspot (Windows: Settings → Mobile hotspot, phone joins it) or USB
cable; phone hotspot does NOT work because Wireless debugging needs the phone to be a Wi-Fi client.

### Profiles → scrcpy args

Common to all DeX profiles (never restrict resizing or multitasking):

```
--new-display=<W>x<H>/<DPI>  --flex-display  --no-vd-destroy-content
--keyboard=uhid  --mouse=sdk  --mouse-bind=++++:bhsn
--window-title="Galaxy DeX (<profile>)"  --shortcut-mod=<mod>
--keep-active  --disable-screensaver  --max-fps=60  --video-bit-rate=<N>M
--stay-awake (USB only)  --video-buffer=50 (Wi-Fi only)  --video-codec=<codec>
--turn-screen-off (--screen off only)  --fullscreen (--fullscreen only)
```

- `--keep-active`: simulated user activity; keeps the phone from sleeping on USB *and* Wi-Fi
  without changing settings. A sleeping phone stops rendering the virtual display ("DeX frozen").
  `--stay-awake` (`stay_on_while_plugged_in`) only works when plugged in, so it is USB-only.
- `--video-buffer=50` over Wi-Fi absorbs jitter, the main cause of stutter/"unresponsive" sessions.
- `--turn-screen-off` is opt-in (`--screen off`): on some Galaxy phones the panel-off puts the
  phone into doze and the DeX display freezes; `dex wake` recovers. Default `on`, `dim` is the safe
  "dark phone" alternative (brightness 0, restored afterwards).

- `--no-vd-destroy-content`: closing the window moves apps to the phone instead of killing them.
- `--mouse-bind=++++:bhsn`: right/middle click reach DeX (context menus in Office) instead of BACK/HOME.
- `--keyboard=uhid`: physical keyboard, layout chosen on phone (Turkish Q) → `dex keyboard`.
- shortcut mod default: macOS `lsuper` (Cmd), Linux/Windows `lalt`. Never `ralt` (Turkish Q AltGr
  types @ # € etc.). Override with config `DEX_SHORTCUT_MOD`.
- `--stay-awake` only when connected over USB (scrcpy ignores/complains otherwise).

| profile | DPI | extras |
|---|---|---|
| code | 160 | `--max-fps=60 --video-bit-rate=16M` audio on |
| school | 140 (more workspace for Word/Excel side by side) | `--max-fps=60 --video-bit-rate=12M` audio on |
| movie | 160 | `--max-fps=60 --video-bit-rate=24M --video-codec=h265 --audio-buffer=80` (window, F11 / MOD+f for fullscreen) |
| mirror | — | no `--new-display/--flex-display`; `--video-bit-rate=12M --max-fps=60 --keyboard=uhid` |

`movie` prints: "Netflix / Disney+ / Prime use DRM: video stays black inside a PC window (Android
blocks capture of protected content). For DRM content use a USB-C→HDMI cable/hub to a monitor/TV
(real DeX), Wireless DeX to a smart TV, or the streaming site in the PC's browser. YouTube, local
files, Plex/Jellyfin work fine here."

Over Wi-Fi lower defaults: bit-rate × 0.5 (code 8M, school 6M, movie 12M), keep 60 fps.

Config file (KEY=VALUE, `#` comments) keys: `DEX_LAST_ENDPOINT`, `DEX_SHORTCUT_MOD`, `DEX_DPI`,
`DEX_RES`, `DEX_EXTRA_ARGS`, `DEX_SCREEN` (on|dim|off), `DEX_FULLSCREEN` (0|1), `DEX_FREEFORM`
(0|1), `DEX_KEYBOARD_HINT_SHOWN`. Write config safely (replace key line or append).

Screen size detection: Linux `xrandr --current` (primary or first connected) or
`xdpyinfo`; Wayland fallback 1600x900. macOS: `system_profiler SPDisplaysDataType` ("Resolution:"
or "UI Looks like:"), else 1600x900. Windows: `[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea`.
Default window res = 80% of that, rounded down to multiples of 8.

### Other behaviour

- Use the bundled `adb`/`scrcpy` by absolute path (don't depend on PATH). Export `ADB` env var to
  scrcpy so it uses the bundled adb. Test overrides: `DEX_ADB`, `DEX_SCRCPY`, `DEX_CONFIG_DIR`,
  `DEX_DRY_RUN=1` (print the scrcpy command, exit 0), `DEX_NO_TUI=1`.
- `tests/fake-phone.sh`: stub adb/scrcpy pair (Galaxy on One UI 9, dozing) that checks the whole
  start flow without hardware (wake, freeform fix on "New display", dim/restore, argument list,
  exit 2 without device). Runs in CI.
- First run: if config has no `DEX_KEYBOARD_HINT_SHOWN`, print Turkish Q hint once and set it.
- Exit codes: 0 ok, 1 usage/runtime error, 2 no device.
- Bash: `set -euo pipefail`, POSIX-ish bash 3.2 compatible (macOS ships bash 3.2: no associative
  arrays, no `${var,,}`, no `mapfile`). Pass shellcheck.
- PowerShell: compatible with Windows PowerShell 5.1 and PowerShell 7. Pass PSScriptAnalyzer
  (default rules; `Write-Host` allowed).

## First-time phone checklist (printed by installer and README)

1. Settings → About phone → Software information → tap **Build number** 7× (Developer options).
2. Settings → Developer options → **USB debugging** ON (cable) and/or **Wireless debugging** ON (Wi-Fi).
3. Connect: plug USB and accept "Allow USB debugging", or run `dex pair`.
4. `dex keyboard` → set physical keyboard layout to **Turkish Q** (once).
5. `dex` — menu: press 1. DeX opens in a window. Resize freely; F11 = fullscreen.
