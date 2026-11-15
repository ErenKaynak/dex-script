#!/usr/bin/env bash
# Smoke test with a fake phone: a stub adb/scrcpy pair that behaves like a Galaxy on One UI 9.
# Checks the start flow end to end without hardware: device selection, wake-up, the freeform
# windowing fix on "New display", screen dim/restore, and the scrcpy argument list.
#   bash tests/fake-phone.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cfg"
log="$tmp/calls.log"

cat > "$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
# Records every call; answers like a connected Galaxy S25 (One UI 9, asleep, freeform option on).
# FAKE_ONEUI / FAKE_FF override the One UI version and the freeform option value.
printf 'adb %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  "devices -l") printf 'List of devices attached\nR5CX1234567 device usb:1-2 product:dm1q model:SM_S931B\n' ;;
  *"getprop ro.product.model"*) echo "SM-S931B" ;;
  *"getprop ro.product.marketname"*) echo "Galaxy S25" ;;
  *"getprop ro.serialno"*) echo "R5CX1234567" ;;
  *"getprop ro.build.version.oneui"*) echo "${FAKE_ONEUI:-90000}" ;;
  *"getprop ro.build.version.sdk"*) echo "${FAKE_SDK:-37}" ;;
  *"settings get global force_desktop_mode_on_external_displays"*) echo "${FAKE_FD:-0}" ;;
  *"dumpsys power"*) echo "  mWakefulness=Dozing" ;;
  *"dumpsys window policy"*) printf 'KeyguardServiceDelegate\n  showing=false\n' ;;
  *"settings get system screen_brightness_mode"*) echo 1 ;;
  *"settings get system screen_brightness"*) echo 180 ;;
  *"settings get global enable_freeform_support"*) echo "${FAKE_FF:-1}" ;;
  *"wm set-display-windowing-mode"*) exit 0 ;;
  version) echo "Android Debug Bridge version 1.0.41" ;;
  *) ;;
esac
EOF
cat > "$tmp/bin/scrcpy" <<'EOF'
#!/usr/bin/env bash
printf 'scrcpy %s\n' "$*" >> "$FAKE_LOG"
case "$*" in --version) echo "scrcpy 5.0.1 <https://github.com/Genymobile/scrcpy>"; exit 0 ;; esac
echo "INFO: ADB device found:"
echo "[server] INFO: Device: [samsung] samsung SM-S931B (Android 17)"
case "$*" in *--new-display*) echo "[server] INFO: New display: 1536x864/160 (id=23)" ;; esac
sleep 0.3
exit 0
EOF
chmod +x "$tmp/bin/adb" "$tmp/bin/scrcpy"

export FAKE_LOG="$log" DEX_ADB="$tmp/bin/adb" DEX_SCRCPY="$tmp/bin/scrcpy" DEX_CONFIG_DIR="$tmp/cfg" DEX_NO_TUI=1

fail() { echo "FAIL: $*"; echo "--- calls:"; cat "$log"; exit 1; }
expect() { grep -qF -- "$1" "$log" || fail "expected call: $1"; }

echo "# dry run prints the scrcpy command"
: > "$log"
export DEX_DRY_RUN=1
out="$(bash "$here/bin/dex" code --res 1536x864 --dpi 160 --screen dim 2>&1)" || fail "dry run exit"
grep -q -- "--new-display=1536x864/160 --flex-display --no-vd-destroy-content" <<< "$out" || fail "virtual display args: $out"
grep -q -- "--keep-active" <<< "$out" || fail "--keep-active missing"
grep -q -- "--stay-awake" <<< "$out" || fail "--stay-awake missing on USB"
grep -q -- "--video-bit-rate=16M" <<< "$out" || fail "code bitrate"
grep -q -- "--turn-screen-off" <<< "$out" && fail "dim mode must not pass --turn-screen-off"
grep -q -- "--mouse=uhid --mouse-bind=++++:bhsn" <<< "$out" || fail "Android 15+: real HID mouse on the DeX display: $out"

echo "# --mouse sdk / config DEX_MOUSE / old Android fall back to sdk"
out="$(bash "$here/bin/dex" code --mouse sdk 2>&1)"
grep -q -- "--mouse=sdk" <<< "$out" || fail "--mouse sdk: $out"
out="$(FAKE_SDK=34 bash "$here/bin/dex" code 2>&1)"
grep -q -- "--mouse=sdk" <<< "$out" || fail "Android 14 must use sdk mouse: $out"
echo "DEX_MOUSE=sdk" >> "$tmp/cfg/config"
out="$(bash "$here/bin/dex" code 2>&1)"
grep -q -- "--mouse=sdk" <<< "$out" || fail "DEX_MOUSE=sdk: $out"
sed -i.bak '/^DEX_MOUSE=/d' "$tmp/cfg/config"
out="$(bash "$here/bin/dex" code --mouse touch 2>&1)" && fail "--mouse touch must be rejected"
out="$(bash "$here/bin/dex" mirror 2>&1)"
grep -q -- "--mouse=" <<< "$out" && fail "mirror keeps scrcpy's default mouse: $out"

echo "# screen off passes --turn-screen-off"
out="$(bash "$here/bin/dex" code --screen-off 2>&1)"
grep -q -- "--turn-screen-off" <<< "$out" || fail "--turn-screen-off missing: $out"

echo "# fullscreen uses the full screen size"
out="$(bash "$here/bin/dex" school --fullscreen 2>&1)"
grep -q -- "--fullscreen" <<< "$out" || fail "--fullscreen missing"
grep -q -- "/140 " <<< "$out" || fail "school dpi 140: $out"

echo "# full start: wake, freeform fix, dim + restore"
unset DEX_DRY_RUN
: > "$log"
out="$(bash "$here/bin/dex" code --screen dim 2>&1)" || fail "start exit code: $out"
expect "input keyevent KEYCODE_WAKEUP"
expect "settings put global enable_freeform_support 0" # One UI 8.5+: option off (title bar works)
expect "settings put global enable_freeform_support 1" # restored afterwards
expect "settings put system screen_brightness 0"
expect "settings put system screen_brightness 180"
expect "settings put system screen_brightness_mode 1"
expect "wm set-display-windowing-mode -d 23 5"
grep -q "Desktop windowing enabled on DeX display 23" <<< "$out" || fail "freeform message: $out"
awk '/wm set-display-windowing-mode/{f=1} /screen_brightness 180/{if(!f){exit 1}}' "$log" || fail "brightness restored before freeform fix"
grep -q "force_desktop_mode_on_external_displays 1" "$log" && fail "force desktop is opt-in"
grep -q "^DEX_PHONE_SERIAL=R5CX1234567$" "$tmp/cfg/config" || fail "phone serial remembered"
grep -q "^DEX_PHONE_NAME=Galaxy S25$" "$tmp/cfg/config" || fail "phone name remembered"

echo "# DEX_FORCE_DESKTOP=1: setting applied for the session and restored"
: > "$log"
echo "DEX_FORCE_DESKTOP=1" >> "$tmp/cfg/config"
FAKE_FD=null bash "$here/bin/dex" code >/dev/null 2>&1 || fail "force desktop start"
expect "settings put global force_desktop_mode_on_external_displays 1"
expect "settings delete global force_desktop_mode_on_external_displays"
sed -i.bak '/^DEX_FORCE_DESKTOP=/d' "$tmp/cfg/config"

echo "# debug: logcat captured to a file"
: > "$log"
out="$(bash "$here/bin/dex" debug 2>&1)" || fail "debug exit: $out"
expect "logcat -c"
ls "$tmp"/cfg/debug-*.log >/dev/null 2>&1 || fail "debug log file missing: $out"
grep -q "Debug log saved" <<< "$out" || fail "debug summary: $out"

echo "# One UI 8.0: freeform option turned on and the unset value restored"
: > "$log"
FAKE_ONEUI=80000 FAKE_FF=null bash "$here/bin/dex" code >/dev/null 2>&1 || fail "One UI 8.0 start"
expect "settings put global enable_freeform_support 1"
expect "settings delete global enable_freeform_support"

echo "# One UI 9 with the option unset: left alone"
: > "$log"
FAKE_FF=null bash "$here/bin/dex" code >/dev/null 2>&1 || fail "unset start"
grep -q "settings put global enable_freeform_support\|settings delete global enable_freeform_support" "$log" && fail "unset option must stay untouched"

echo "# config DEX_FREEFORM_SUPPORT=1 overrides the One UI default"
: > "$log"
echo "DEX_FREEFORM_SUPPORT=1" >> "$tmp/cfg/config"
FAKE_FF=null bash "$here/bin/dex" code >/dev/null 2>&1 || fail "override start"
expect "settings put global enable_freeform_support 1"
sed -i.bak '/^DEX_FREEFORM_SUPPORT=/d' "$tmp/cfg/config"

echo "# mirror does not touch freeform"
: > "$log"
bash "$here/bin/dex" mirror >/dev/null 2>&1 || fail "mirror exit"
grep -q "settings put global enable_freeform_support" "$log" && fail "mirror must not change freeform support"
grep -q "wm set-display-windowing-mode" "$log" && fail "mirror must not force windowing (no New display line expected)"

echo "# --no-freeform skips the fix"
: > "$log"
bash "$here/bin/dex" code --no-freeform >/dev/null 2>&1 || fail "no-freeform exit"
grep -q "wm set-display-windowing-mode" "$log" && fail "--no-freeform must skip the windowing fix"

echo "# doctor"
out="$(bash "$here/bin/dex" doctor 2>&1)" || fail "doctor exit: $out"
grep -q "One UI:  9.0" <<< "$out" || fail "doctor One UI: $out"
grep -q "mouse mode:       uhid" <<< "$out" || fail "doctor mouse: $out"
grep -q "remembered: Galaxy S25" <<< "$out" || fail "doctor remembered phone: $out"

echo "# wake"
: > "$log"
bash "$here/bin/dex" wake >/dev/null 2>&1 || fail "wake exit"
expect "input -d 0 keyevent KEYCODE_WAKEUP"

echo "# connect: remembered phone -> mDNS picks the remembered serial, endpoint + IP saved"
cat > "$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
printf 'adb %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  "devices -l") printf 'List of devices attached\n192.168.1.5:37123 device product:dm1q model:SM_S931B\n' ;;
  "mdns services") printf 'List of discovered mdns services\nadb-OTHER000000-abcdef\t_adb-tls-connect._tcp\t192.168.1.9:41000\nadb-R5CX1234567-abcdef\t_adb-tls-connect._tcp\t192.168.1.5:37123\n' ;;
  "connect 192.168.1.5:37123") echo "connected to 192.168.1.5:37123" ;;
  connect*) echo "failed to connect" ;;
  *"getprop ro.serialno"*) echo "R5CX1234567" ;;
  *"getprop ro.product.marketname"*) echo "Galaxy S25" ;;
  *) ;;
esac
EOF
: > "$log"
out="$(bash "$here/bin/dex" connect 2>&1)" || fail "connect exit: $out"
expect "connect 192.168.1.5:37123"
grep -q "connect 192.168.1.9" "$log" && fail "must prefer the remembered phone's mDNS entry"
grep -q "^DEX_LAST_ENDPOINT=192.168.1.5:37123$" "$tmp/cfg/config" || fail "endpoint saved"
grep -q "^DEX_LAST_IP=192.168.1.5$" "$tmp/cfg/config" || fail "ip saved"

echo "# remembered serial comes from the phone just connected, not the first TCP device"
grep -q "^DEX_PHONE_SERIAL=R5CX1234567$" "$tmp/cfg/config" || fail "serial after connect"
grep -q "shell getprop ro.serialno" "$log" || fail "serial read after connect"
grep -q "adb -s 192.168.1.5:37123 shell getprop ro.serialno" "$log" || fail "serial must be read from the connected endpoint: $(grep serialno "$log")"

echo "# connect <port>: bare port uses the remembered IP"
: > "$log"
bash "$here/bin/dex" connect 37123 >/dev/null 2>&1 || fail "connect port exit"
expect "connect 192.168.1.5:37123"

echo "# no device, remembered phone: help mentions it, no pairing code asked (non-interactive)"
cat > "$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
case "$*" in "devices -l") echo "List of devices attached" ;; connect*) echo "failed to connect" ;; *) ;; esac
EOF
set +e; out="$(bash "$here/bin/dex" code 2>&1)"; code=$?; set -e
[ "$code" -eq 2 ] || fail "remembered/no device exit code $code: $out"
grep -q "Remembered: Galaxy S25 (last at 192.168.1.5)" <<< "$out" || fail "remembered phone hint: $out"
grep -q "Trying last endpoint 192.168.1.5:37123" <<< "$out" || fail "last endpoint tried: $out"

echo "# no device -> exit 2"
cat > "$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
case "$*" in "devices -l") echo "List of devices attached" ;; *) ;; esac
EOF
set +e; bash "$here/bin/dex" >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] || fail "no device exit code $code"

echo "ALL OK"
