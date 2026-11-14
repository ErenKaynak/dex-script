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
# Records every call; answers like a connected Galaxy S25 (One UI 9, asleep, freeform unset).
printf 'adb %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  "devices -l") printf 'List of devices attached\nR5CX1234567 device usb:1-2 product:dm1q model:SM_S931B\n' ;;
  *"getprop ro.product.model"*) echo "SM-S931B" ;;
  *"getprop ro.build.version.oneui"*) echo "90000" ;;
  *"getprop ro.build.version.sdk"*) echo "37" ;;
  *"dumpsys power"*) echo "  mWakefulness=Dozing" ;;
  *"dumpsys window policy"*) printf 'KeyguardServiceDelegate\n  showing=false\n' ;;
  *"settings get system screen_brightness_mode"*) echo 1 ;;
  *"settings get system screen_brightness"*) echo 180 ;;
  *"settings get global enable_freeform_support"*) echo null ;;
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
echo "$out" | grep -q -- "--new-display=1536x864/160 --flex-display --no-vd-destroy-content" || fail "virtual display args: $out"
echo "$out" | grep -q -- "--keep-active" || fail "--keep-active missing"
echo "$out" | grep -q -- "--stay-awake" || fail "--stay-awake missing on USB"
echo "$out" | grep -q -- "--video-bit-rate=16M" || fail "code bitrate"
echo "$out" | grep -q -- "--turn-screen-off" && fail "dim mode must not pass --turn-screen-off"

echo "# screen off passes --turn-screen-off"
out="$(bash "$here/bin/dex" code --screen-off 2>&1)"
echo "$out" | grep -q -- "--turn-screen-off" || fail "--turn-screen-off missing: $out"

echo "# fullscreen uses the full screen size"
out="$(bash "$here/bin/dex" school --fullscreen 2>&1)"
echo "$out" | grep -q -- "--fullscreen" || fail "--fullscreen missing"
echo "$out" | grep -q -- "/140 " || fail "school dpi 140: $out"

echo "# full start: wake, freeform fix, dim + restore"
unset DEX_DRY_RUN
: > "$log"
out="$(bash "$here/bin/dex" code --screen dim 2>&1)" || fail "start exit code: $out"
expect "input keyevent KEYCODE_WAKEUP"
expect "settings put global enable_freeform_support 1"
expect "settings delete global enable_freeform_support"
expect "settings put system screen_brightness 0"
expect "settings put system screen_brightness 180"
expect "settings put system screen_brightness_mode 1"
expect "wm set-display-windowing-mode -d 23 5"
echo "$out" | grep -q "Desktop windowing enabled on DeX display 23" || fail "freeform message: $out"
awk '/wm set-display-windowing-mode/{f=1} /screen_brightness 180/{if(!f){exit 1}}' "$log" || fail "brightness restored before freeform fix"

echo "# mirror does not touch freeform"
: > "$log"
bash "$here/bin/dex" mirror >/dev/null 2>&1 || fail "mirror exit"
grep -q "enable_freeform_support 1" "$log" && fail "mirror must not change freeform support"
grep -q "wm set-display-windowing-mode" "$log" && fail "mirror must not force windowing (no New display line expected)"

echo "# --no-freeform skips the fix"
: > "$log"
bash "$here/bin/dex" code --no-freeform >/dev/null 2>&1 || fail "no-freeform exit"
grep -q "wm set-display-windowing-mode" "$log" && fail "--no-freeform must skip the windowing fix"

echo "# doctor"
out="$(bash "$here/bin/dex" doctor 2>&1)" || fail "doctor exit: $out"
echo "$out" | grep -q "One UI:  9.0" || fail "doctor One UI: $out"

echo "# wake"
: > "$log"
bash "$here/bin/dex" wake >/dev/null 2>&1 || fail "wake exit"
expect "input -d 0 keyevent KEYCODE_WAKEUP"

echo "# no device -> exit 2"
cat > "$tmp/bin/adb" <<'EOF'
#!/usr/bin/env bash
case "$*" in "devices -l") echo "List of devices attached" ;; *) ;; esac
EOF
set +e; bash "$here/bin/dex" >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] || fail "no device exit code $code"

echo "ALL OK"
