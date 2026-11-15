<img src="assets/icon.svg" width="64" height="64" alt="">

# dex-script — Samsung DeX in a window on any PC

Run **Samsung DeX** from a Galaxy phone (One UI 8+, e.g. Galaxy S25 on One UI 9) inside a
**resizable window** on Linux, macOS or Windows — over **USB or Wi-Fi**, no admin rights needed.

It uses [scrcpy](https://github.com/Genymobile/scrcpy)'s virtual display: since One UI 8, DeX runs
on any virtual display, and `--flex-display` resizes that display with the window, so DeX apps can
be snapped, resized and multitasked like on a real desktop. `dex` also applies the fixes that
One UI 8.5/9 needs (see [How it works](#how-it-works)).

## Install (one line)

**Linux / macOS**

```bash
curl -fsSL https://dex.erenkaynak.tr/linux | bash
```

**Windows 10 / 11** (PowerShell)

```powershell
irm https://dex.erenkaynak.tr/windows | iex
```

<details><summary>Direct GitHub links (if the short links are blocked)</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.ps1 | iex
```

</details>

No sudo / admin, no package manager. Everything goes in your user folder, so it also works on
locked-down school PCs that reset on reboot. Just re-run the one-liner, it takes a few seconds.

## Phone setup (once)

1. **Settings → About phone → Software information** → tap **Build number** 7 times.
2. **Settings → Developer options** → turn on **USB debugging** (cable) and/or **Wireless debugging** (Wi-Fi).
3. Connect: plug in the USB cable and accept **Allow USB debugging**, or press `p` in the menu (`dex pair`).
4. Press `k` (`dex keyboard`) and set the physical keyboard layout to **Turkish Q** (or yours).
5. Press `1`. DeX opens in a window. Resize it freely; **F11** toggles fullscreen.

## Usage

Run `dex` and pick a number (the menu refreshes itself when you plug the phone in; Enter restarts
the last profile):

```
             _                   _
    ___ _ __| | ____ _        __| | _____  __
   / _ \ '__| |/ / _` |_____ / _` |/ _ \ \/ /
  |  __/ |  |   < (_| |_____| (_| |  __/>  <
   \___|_|  |_|\_\__,_|      \__,_|\___/_/\_\

  ╭──────────────────────────────────────────────────────────╮
  │ Galaxy DeX on your PC                       scrcpy 5.0.1 │
  ├──────────────────────────────────────────────────────────┤
  │ Phone    Galaxy S25 · One UI 9.0 · USB               87% │
  │ Settings phone on · window · 1536x864 auto @ auto        │
  ├──────────────────────────────────────────────────────────┤
  │  1  Code      crisp text: coding, T3, browser       last │
  │  2  School    more room: Word / Excel side by side       │
  │  3  Movie     high bitrate, H.265, smooth audio          │
  │  4  Mirror    plain phone screen, no DeX                 │
  │                                                          │
  │  p  Pair      Wi-Fi pairing with a code (no cable)       │
  │  c  Connect   reconnect over Wi-Fi                       │
  │  w  Wi-Fi     USB plugged in -> switch to Wi-Fi          │
  │  k  Keyboard  phone keyboard layout (Turkish Q)          │
  │  s  Screen    phone panel while DeX runs: on / dim / off │
  │  f  Window    toggle window / fullscreen start           │
  │  r  Size      set window size and DPI                    │
  │  d  Doctor    versions, devices, One UI check            │
  │  x  Wake      unfreeze a stuck DeX window                │
  │  u  Update    re-run the installer                       │
  │  q  Quit                                                 │
  ╰──────────────────────────────────────────────────────────╯
  Enter = code · F11 fullscreen in DeX · Alt+q closes DeX · menu refreshes itself
  Choose ›
```

Prefer buttons? `dex gui` opens a small native window instead of the terminal menu (zenity or
kdialog on Linux, built-in dialogs on macOS, a WinForms window on Windows). The desktop / Start
Menu launcher "Galaxy DeX" uses it when available; the terminal menu is always one `dex` away.

Everything is also a plain command, for scripts and shortcuts:

| Command | What it does |
|---|---|
| `dex code` | DeX tuned for crisp text (coding, T3, browser) |
| `dex school` | DeX with more workspace (Word / Excel side by side) |
| `dex movie` | DeX with higher bitrate + H.265 + smoother audio |
| `dex mirror` | Plain phone-screen mirror, no DeX |
| `dex pair` | Wireless pairing with a 6-digit code (no cable) |
| `dex connect [ip:port]` | Reconnect over Wi-Fi (auto-discovers the phone) |
| `dex wifi` | USB plugged → switch to Wi-Fi, then unplug (until phone reboot) |
| `dex gui` | Small graphical launcher (same actions as the menu) |
| `dex wake` | Wake the phone / unfreeze a stuck DeX window |
| `dex keyboard` | Open the phone's physical keyboard settings |
| `dex doctor` | Show versions, devices, One UI version, power state |
| `dex update` / `dex uninstall` | Update or remove everything |

Options: `--res 1920x1080`, `--dpi 140`, `--usb`, `--wifi`, `--screen on|dim|off`,
`--fullscreen` (start at your monitor's resolution, like a real DeX monitor), `--no-freeform`,
and `-- <extra scrcpy args>`.

Profiles only change quality settings. Every profile keeps the window resizable and DeX fully
multitasking. Closing the window doesn't kill your apps; they move back to the phone.

Settings persist in `~/.config/dex/config` (Windows: `%APPDATA%\dex\config`), e.g.
`DEX_SCREEN=dim`, `DEX_FULLSCREEN=1`, `DEX_DPI=150`, `DEX_RES=2560x1440`, `DEX_SHORTCUT_MOD=lalt`,
`DEX_EXTRA_ARGS=...`. The menu keys `s`, `f` and `r` write these for you.

### Phone screen while DeX runs

| Mode (`s` key / `--screen`) | What happens |
|---|---|
| `on` (default) | The phone stays awake and lit. Safest: DeX never freezes. |
| `dim` | Brightness goes to minimum while DeX runs and is restored afterwards. Looks like "screen off" without the risks. |
| `off` | scrcpy turns the panel off. On some Galaxy phones the phone then dozes and the DeX window stops responding. If that happens: `dex wake` (menu `x`) and switch back to `on` or `dim`. |

In every mode `dex` keeps the phone awake (simulated user activity, works over Wi-Fi too), so you
no longer need to tap the phone to keep DeX alive.

### Shortcuts

scrcpy shortcuts use **Left Alt** (Linux/Windows) or **Cmd** (macOS): `MOD+f` fullscreen,
`MOD+q` quit, `MOD+v` paste PC clipboard, `MOD+o` turn phone screen off, `MOD+Shift+o` back on,
`MOD+Shift+r` reset the video if it hangs. Right Alt (AltGr) is left alone so Turkish Q characters
like `@ # € |` type normally. Copy/paste between PC and phone syncs automatically.

## Wi-Fi at school

School PCs forget the pairing on every reboot, so each session:

1. Phone → Developer options → **Wireless debugging** → **Pair device with pairing code**.
2. On the PC: run the one-liner, then `dex`, press `p`, and type the IP:port and the 6-digit code.
3. Press `2` (School).

If pairing times out, the school Wi-Fi probably isolates devices from each other. Options:

- **PC hotspot**: Windows → Settings → Network → **Mobile hotspot**, connect the phone to it, then
  `dex pair`. (A phone hotspot does *not* work: Wireless debugging needs the phone to be a Wi-Fi
  client.)
- **USB cable**: always works, lowest latency, charges the phone. `dex wifi` lets you unplug
  after the first connection.

## Netflix and other DRM content

Netflix, Disney+, Prime Video and similar apps protect their video. Android refuses to let anything
capture it, so **inside a PC window the video stays black**. This is a platform rule, and no
non-root tool can get around it. For DRM content:

- **USB-C → HDMI cable or hub** to a monitor/TV: real DeX, full Netflix with HDCP. Plug in and
  DeX starts on the TV. Use a hub with USB-C PD to charge at the same time.
- **Wireless DeX to a smart TV** (Samsung TVs and most Miracast TVs): Quick panel → **DeX** → pick
  the TV.
- **The streaming site in the PC's own browser.** Simplest when you're already at a PC.

YouTube, local video files, Plex/Jellyfin and most non-DRM players work fine in `dex movie`.

## Troubleshooting

- **Apps open fullscreen, can't be moved or resized (no multitasking)**: that is One UI 8.5/9
  (Android 16 QPR2+) refusing desktop windowing on virtual displays. `dex` fixes it automatically
  when the DeX display appears (you'll see "Desktop windowing enabled on DeX display N"). Apps that
  were already open before that line stay fullscreen: close and reopen them. If the line never
  shows up, run `dex doctor` and check the One UI version.
- **Window frozen / unresponsive**: the phone went to sleep or locked. `dex wake` (menu `x`), unlock
  the phone, or press `Alt+Shift+r` in the window. Over Wi-Fi, `dex` already adds a 50 ms video
  buffer and halves the bitrate; on a bad network use 5 GHz, `--res 1600x900`, or USB.
- **Black window / plain launcher instead of DeX**: run `dex doctor`. DeX on a virtual display
  needs One UI 8 or newer. Make sure the phone is awake and unlocked when you start.
- **Lock screen inside the DeX window, dock shrunk to a few buttons**: unlock the phone. Samsung
  keeps DeX running behind the lock screen but blocks typing until you unlock.
- **"unauthorized"**: unlock the phone and accept the *Allow USB debugging* prompt.
- **Wrong characters when typing**: run `dex keyboard` → choose Turkish Q.
- **Laggy over Wi-Fi**: use 5 GHz Wi-Fi, or `dex --res 1600x900`, or USB.

## How it works

`install.sh` / `install.ps1` download the pinned official scrcpy release (it bundles `adb`),
verify its SHA-256, and install the `dex` wrapper. The wrapper picks the device (USB first, then
Wi-Fi via mDNS / last known address), wakes the phone, and starts scrcpy with
`--new-display=WxH/DPI --flex-display --no-vd-destroy-content --keyboard=uhid --keep-active` plus
the profile settings. While scrcpy runs, `dex` watches its log for the new display id and runs
`wm set-display-windowing-mode -d <id> 5` (freeform) on the phone, which is what One UI 8.5/9
needs for movable, resizable DeX windows. See [docs/DESIGN.md](docs/DESIGN.md).
