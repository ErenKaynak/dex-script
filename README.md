<img src="assets/icon.svg" width="64" height="64" alt="">

# dex-script — Samsung DeX in a window on any PC

Run **Samsung DeX** from a Galaxy phone (One UI 8+, e.g. Galaxy S25 on One UI 9) inside a
**resizable window** on Linux, macOS or Windows — over **USB or Wi-Fi**, no admin rights needed.

It uses [scrcpy](https://github.com/Genymobile/scrcpy)'s virtual display: since One UI 8, DeX runs
on any virtual display, and `--flex-display` resizes that display with the window, so DeX apps can
be snapped, resized and multitasked like on a real desktop.

## Install (one line)

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.sh | bash
```

**Windows 10 / 11** (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.ps1 | iex
```

No sudo / admin, no package manager. Everything goes in your user folder, so it also works on
locked-down school PCs that reset on reboot. Just re-run the one-liner, it takes a few seconds.

## Phone setup (once)

1. **Settings → About phone → Software information** → tap **Build number** 7 times.
2. **Settings → Developer options** → turn on **USB debugging** (cable) and/or **Wireless debugging** (Wi-Fi).
3. Connect: plug in the USB cable and accept **Allow USB debugging**, or run `dex pair` (no cable).
4. Run `dex keyboard` and set the physical keyboard layout to **Turkish Q** (or yours).
5. Run `dex`. DeX opens in a window. Resize it freely; **F11** toggles fullscreen.

## Usage

| Command | What it does |
|---|---|
| `dex` / `dex code` | DeX tuned for crisp text (coding, T3, browser) |
| `dex school` | DeX with more workspace (Word / Excel side by side) |
| `dex movie` | DeX with higher bitrate + H.265 + smoother audio |
| `dex mirror` | Plain phone-screen mirror, no DeX |
| `dex pair` | Wireless pairing with a 6-digit code (no cable) |
| `dex connect [ip:port]` | Reconnect over Wi-Fi (auto-discovers the phone) |
| `dex wifi` | USB plugged → switch to Wi-Fi, then unplug (until phone reboot) |
| `dex keyboard` | Open the phone's physical keyboard settings |
| `dex doctor` | Show versions, devices, One UI version |
| `dex update` / `dex uninstall` | Update or remove everything |

Options: `--res 1920x1080`, `--dpi 140`, `--usb`, `--wifi`, `--screen-off` (phone panel off while
running), `--fullscreen`, and `-- <extra scrcpy args>`.

Profiles only change quality settings. Every profile keeps the window resizable and DeX fully
multitasking. Closing the window doesn't kill your apps; they move back to the phone.

Settings persist in `~/.config/dex/config` (Windows: `%APPDATA%\dex\config`), e.g.
`DEX_DPI=150`, `DEX_RES=2560x1440`, `DEX_SHORTCUT_MOD=lalt`, `DEX_EXTRA_ARGS=...`.

### Shortcuts

scrcpy shortcuts use **Left Alt** (Linux/Windows) or **Cmd** (macOS): `MOD+f` fullscreen,
`MOD+q` quit, `MOD+v` paste PC clipboard, `MOD+o` turn phone screen off. Right Alt (AltGr) is left
alone so Turkish Q characters like `@ # € |` type normally. Copy/paste between PC and phone syncs
automatically.

## Wi-Fi at school

School PCs forget the pairing on every reboot, so each session:

1. Phone → Developer options → **Wireless debugging** → **Pair device with pairing code**.
2. On the PC: run the one-liner, then `dex pair`, and type the IP:port and the 6-digit code.
3. `dex school`

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

- **Black window / plain launcher instead of DeX**: run `dex doctor`. DeX on a virtual display
  needs One UI 8 or newer.
- **"unauthorized"**: unlock the phone and accept the *Allow USB debugging* prompt.
- **Wrong characters when typing**: run `dex keyboard` → choose Turkish Q.
- **Laggy over Wi-Fi**: use 5 GHz Wi-Fi, or `dex --res 1600x900`, or USB.

## How it works

`install.sh` / `install.ps1` download the pinned official scrcpy release (it bundles `adb`),
verify its SHA-256, and install the `dex` wrapper. The wrapper picks the device (USB first, then
Wi-Fi via mDNS / last known address) and starts scrcpy with
`--new-display=WxH/DPI --flex-display --no-vd-destroy-content --keyboard=uhid` plus the profile
settings. See [docs/DESIGN.md](docs/DESIGN.md).
