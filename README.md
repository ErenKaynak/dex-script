<img src="assets/icon.svg" width="64" height="64" alt="">

# dex-script — Samsung DeX in a window on any PC

Run **Samsung DeX** from a Galaxy phone (One UI 8+, e.g. Galaxy S25 on One UI 9) inside a
**resizable window** on Linux, macOS or Windows — over **USB or Wi-Fi**, no admin rights needed.

It uses [scrcpy](https://github.com/Genymobile/scrcpy) to mirror a second display of the phone.
On One UI 8.0 that is scrcpy's own virtual display, which resizes with the window. On One UI 8.5/9
(Android 16 QPR2+/17) the stock scrcpy server creates that display in a way Android no longer
gives desktop windows (title bars, drag, resize, minimize), so `dex` ships a patched server that
fixes the display flags, and falls back to a system *overlay display* when the patched server is
not available (see [How it works](#how-it-works)).

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
  │ Settings phone on · window · mouse auto · 1536x864 @ auto│
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
  │  m  Mouse     real HID mouse (uhid) / touch (sdk)        │
  │  o  Display   auto / overlay (One UI 9 windows) / virtual│
  │  v  Server    auto / patched (dex build) / stock scrcpy  │
  │  d  Doctor    versions, devices, One UI check            │
  │  x  Wake      unfreeze a stuck DeX window                │
  │  l  Log       start Code with a phone log (bug reports)  │
  │  u  Update    re-run the installer                       │
  │  q  Quit                                                 │
  ╰──────────────────────────────────────────────────────────╯
  Enter = code · F11 fullscreen in DeX · Alt+q closes DeX · menu refreshes itself
  Choose ›
```

Everything is also a plain command, for scripts and shortcuts:

| Command | What it does |
|---|---|
| `dex code` | DeX tuned for crisp text (coding, T3, browser) |
| `dex school` | DeX with more workspace (Word / Excel side by side) |
| `dex movie` | DeX with higher bitrate + H.265 + smoother audio |
| `dex mirror` | Plain phone-screen mirror, no DeX |
| `dex pair` | Wireless pairing with a 6-digit code (no cable). Once per PC: `dex` remembers the phone |
| `dex connect [ip:port]` | Reconnect over Wi-Fi (auto-discovers the phone; a remembered phone only needs the new port) |
| `dex wifi` | USB plugged → switch to Wi-Fi, then unplug (until phone reboot) |
| `dex wake` | Wake the phone / unfreeze a stuck DeX window |
| `dex keyboard` | Open the phone's physical keyboard settings |
| `dex doctor` | Show versions, devices, One UI version, power state, mouse mode |
| `dex debug` | Start DeX with a phone log for bug reports (see Troubleshooting) |
| `dex update` / `dex uninstall` | Update or remove everything |

Options: `--res 1920x1080`, `--dpi 140`, `--usb`, `--wifi`, `--screen on|dim|off`,
`--fullscreen` (start at your monitor's resolution, like a real DeX monitor), `--no-freeform`,
`--mouse uhid|sdk`, `--display auto|overlay|virtual`, `--server auto|patched|stock`, `--debug`,
and `-- <extra scrcpy args>`.

Profiles only change quality settings. Every profile keeps the window resizable and DeX fully
multitasking. Closing the window doesn't kill your apps; they move back to the phone.

Settings persist in `~/.config/dex/config` (Windows: `%APPDATA%\dex\config`), e.g.
`DEX_SCREEN=dim`, `DEX_FULLSCREEN=1`, `DEX_DPI=150`, `DEX_RES=2560x1440`, `DEX_SHORTCUT_MOD=lalt`,
`DEX_MOUSE=sdk`, `DEX_MOUSE_ACCEL=1`, `DEX_VIDEO_BUFFER=50`, `DEX_IME=local`, `DEX_DISPLAY=virtual`,
`DEX_SERVER=stock`, `DEX_EXTRA_ARGS=...`. The menu keys
`s`, `f`, `r`, `m`, `o` and `v` write these for you.

### Windows on One UI 8.5 / 9: patched server or overlay display

Android 16 QPR2+ (the base of One UI 8.5/9) only runs desktop windowing, the thing that gives
windows a title bar you can drag, resize buttons and minimize, on displays whose content mode can
switch between "mirror" and "extend". The stock scrcpy server creates its virtual display as
"always show system decorations", which excludes it: DeX starts on it and apps open as frameless
freeform windows that cannot be moved. `dex` has two answers:

- **Patched server** (`v` → patched, default on Android 17+ when installed): a build of the
  scrcpy 5.0.1 server with [upstream PR #7055](https://github.com/Genymobile/scrcpy/pull/7055)
  applied, which creates the virtual display with the right flag. You keep everything: the
  display resizes with the window, nothing shows on the phone. The installer downloads it from
  this repo's releases (built by CI from the official source plus the 2-hunk patch in
  [`server/`](server/)); `dex update` fetches it if it was missing.
- **Overlay display** (`o` → overlay, default on One UI 8.5+ when the patched server is not
  installed): a system overlay display (developer setting `overlay_display_devices`) at your
  window size, which DeX manages like a real external monitor, mirrored with `--display-id`. Side
  effects: Android draws a small preview of it on the phone screen (ignore it; `s` dims the
  phone), and its size is fixed for the session (`r` sets it; the window still scales). It is
  removed when DeX closes and your apps move back to the phone.

### Mouse: why the DeX window captures your pointer

Since One UI 8.5, DeX window title bars (drag, minimize / maximize / close, edge resizing) react
to a **mouse**, but treat injected touch-style clicks like finger taps (tap-and-hold to move) or
ignore them. So `dex` makes scrcpy create a **real HID mouse on the phone** (`--mouse=uhid`) and
bind it to the DeX display: DeX sees exactly what it sees with a mouse plugged into a DeX dock.
The price is that the DeX window *captures* the PC pointer while it has focus. **Press Alt**
(Cmd on macOS) to give the pointer back to the PC, click the window to capture it again. If you
prefer the old behaviour (pointer never captured, title bars may not drag), press `m` in the menu
or use `--mouse sdk`. Android 14 and older phones fall back to `sdk` automatically.

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

## Wi-Fi: pair once, then just connect

Pairing is needed **once per PC**: the phone keeps the PC's key (Wireless debugging → *Paired
devices*) and `dex` remembers the phone (name, serial, last IP). What changes is the *connect
port*: Android picks a new one every time Wireless debugging restarts or the phone reboots.

- Same Wi-Fi, port unchanged → `dex` finds the phone by itself (mDNS or the last address).
- Port changed → the menu says "not connected: Galaxy S25 (last at 192.168.1.5) · c = connect".
  Press `c` and type the port shown under Wireless debugging → **IP address & Port**. No code.
- Only if the phone forgot the PC (e.g. you removed it from *Paired devices*, or a school PC was
  wiped): `p` to pair again.

School PCs reset on every reboot, so there each session is: run the one-liner, `dex`, `p`,
type the pairing IP:port + 6-digit code, then `2` (School).

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
- **Apps open as windows without any title bar (can't move, resize or minimize them)**: that is
  One UI 8.5/9 on the stock server's virtual display (WM Shell logs "desktop not supported" for
  it). `dex doctor` must say `server: patched` or `display mode: overlay`; menu `v` / `o` set
  them (`u` first if the patched server is missing). Keep the mouse mode `uhid` (`m`) so the
  title bars get real mouse events. Still stuck? Press `l` (or
  `dex debug`), open an app, try to drag its title bar and press its buttons, close DeX, and open
  an issue with the `debug-*.log.filtered` and `.dumpsys` files from `~/.config/dex`
  (Windows: `%APPDATA%\dex`).
- **A small picture of the DeX screen floats on the phone**: that is Android's preview of the
  overlay display. It cannot be hidden; dim the phone (`s`) or put it face down.
- **Window frozen / unresponsive**: the phone went to sleep or locked. `dex wake` (menu `x`), unlock
  the phone, or press `Alt+Shift+r` in the window. Over Wi-Fi, `dex` already adds a 50 ms video
  buffer and halves the bitrate; on a bad network use 5 GHz, `--res 1600x900`, or USB.
- **Black window / plain launcher instead of DeX**: run `dex doctor`. DeX on a virtual display
  needs One UI 8 or newer. Make sure the phone is awake and unlocked when you start.
- **Lock screen inside the DeX window, dock shrunk to a few buttons**: unlock the phone. Samsung
  keeps DeX running behind the lock screen but blocks typing until you unlock.
- **"unauthorized"**: unlock the phone and accept the *Allow USB debugging* prompt.
- **Wrong characters when typing**: run `dex keyboard` → choose Turkish Q.
- **Laggy pointer or blurry picture over Wi-Fi**: with the real HID mouse (`uhid`) the pointer is
  drawn by the phone, so every mouse move goes PC → phone and comes back inside the video.
  Its lag is the Wi-Fi round trip plus encoding, and the picture uses half the USB bitrate
  (8 Mbit/s in `code`) so big redraws get blocky. Video and mouse share one adb connection,
  so a large video frame briefly holds the mouse packets back. `dex` already removes the
  50 ms video buffer with `uhid` and turns off the phone's mouse acceleration for the session
  (bursts of delayed moves made the pointer jump far). What helps most after that: 5 GHz
  Wi-Fi close to the router, the phone and PC on the same network (no VPN), a smaller
  `--res 1600x900`, or the USB cable. To trade sharpness for bandwidth set e.g.
  `DEX_EXTRA_ARGS=--video-bit-rate=12M`, or try `m` → `sdk`: the pointer is then drawn by the
  PC and has no lag at all.
- **The on-screen keyboard pops up for every text field**: `dex` hides it on the DeX screen
  (`--display-ime-policy=hide`); your PC keyboard keeps typing. Set `DEX_IME=local` to get it
  back inside DeX, or `DEX_IME=default` to leave Android's choice.

## How it works

`install.sh` / `install.ps1` download the pinned official scrcpy release (it bundles `adb`),
verify its SHA-256, and install the `dex` wrapper. The wrapper picks the device (USB first, then
Wi-Fi via mDNS / last known address / the remembered phone), wakes the phone, and starts scrcpy
with `--keyboard=uhid --mouse=uhid --keep-active` plus the profile settings (the UHID mouse is
bound to the mirrored display, Android 15+). With the virtual display (One UI 8.0, or Android 17+
with the patched server via `SCRCPY_SERVER_PATH`) it adds `--new-display=WxH/DPI --flex-display
--no-vd-destroy-content` and runs `wm set-display-windowing-mode -d <id> 5` (freeform) when the
display appears. With the overlay display (One UI 8.5/9, stock server) it first runs `settings put
global overlay_display_devices WxH/DPI`, waits for the overlay display id, forces freeform on it
and mirrors it with `--display-id=<id>`; when DeX closes it deletes the setting again. See
[docs/DESIGN.md](docs/DESIGN.md) for why.
