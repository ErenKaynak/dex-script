#!/usr/bin/env bash
# Galaxy DeX on PC - installer for Linux (x86_64) and macOS (Apple Silicon / Intel).
#   curl -fsSL https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.sh | bash
# No sudo, everything lives under your home directory.
set -euo pipefail

main() {
  local repo="${DEX_REPO:-ErenKaynak/dex-script}"
  local branch="${DEX_BRANCH:-main}"
  local raw="https://raw.githubusercontent.com/$repo/$branch"
  local ver="${DEX_SCRCPY_VERSION:-5.0.1}"
  local root="${DEX_HOME:-$HOME/.local/share/dex}"
  local bindir="$HOME/.local/bin"
  local marker="# dex"

  local c_ok="" c_err="" c_dim="" c_off=""
  if [ -t 1 ]; then
    c_ok=$'\033[32m'; c_err=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
  fi
  say() { printf '%s\n' "$*"; }
  ok() { printf '%s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
  die() { printf '%s✗ %s%s\n' "$c_err" "$*" "$c_off" >&2; exit 1; }

  # --- platform -----------------------------------------------------------
  local os arch asset
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64) asset="scrcpy-linux-x86_64-v$ver.tar.gz" ;;
    Darwin/arm64) asset="scrcpy-macos-aarch64-v$ver.tar.gz" ;;
    Darwin/x86_64) asset="scrcpy-macos-x86_64-v$ver.tar.gz" ;;
    *) die "Unsupported platform: $os/$arch (need Linux x86_64 or macOS). On Windows use install.ps1." ;;
  esac

  # --- helpers --------------------------------------------------------------
  fetch() { # fetch URL DEST
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$2" "$1"
    else
      die "Need curl or wget."
    fi
  }
  sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "$1" | awk '{print $1}'
    else
      die "Need sha256sum or shasum to verify the download."
    fi
  }

  command -v tar >/dev/null 2>&1 || die "Need tar."
  mkdir -p "$root" "$bindir"
  local tmp
  tmp="$(mktemp -d "$root/.tmp.XXXXXX")"
  DEX_TMP="$tmp" # global: the EXIT trap runs after main's locals are gone
  trap 'rm -rf "${DEX_TMP:-}"' EXIT

  # --- scrcpy -----------------------------------------------------------------
  local installed=""
  [ -f "$root/scrcpy/VERSION" ] && installed="$(cat "$root/scrcpy/VERSION")"
  if [ "$installed" = "$ver" ] && [ -x "$root/scrcpy/scrcpy" ]; then
    ok "scrcpy $ver already installed"
  else
    say "Downloading scrcpy $ver ($asset)..."
    local base="https://github.com/Genymobile/scrcpy/releases/download/v$ver"
    fetch "$base/$asset" "$tmp/$asset" || die "Download failed: $base/$asset"
    fetch "$base/SHA256SUMS.txt" "$tmp/SHA256SUMS.txt" || die "Could not download SHA256SUMS.txt"
    local want got
    want="$(awk -v a="$asset" '$2==a || $2=="*" a {print $1; exit}' "$tmp/SHA256SUMS.txt")"
    [ -n "$want" ] || die "No checksum for $asset in SHA256SUMS.txt"
    got="$(sha256_of "$tmp/$asset")"
    [ "$want" = "$got" ] || die "SHA256 mismatch for $asset (expected $want, got $got). Aborting."
    ok "SHA256 verified"

    mkdir "$tmp/x"
    tar -xzf "$tmp/$asset" -C "$tmp/x"
    local top
    top="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$top" ] || [ ! -x "$top/scrcpy" ]; then die "Unexpected archive layout."; fi
    if [ -x "$root/scrcpy/adb" ]; then "$root/scrcpy/adb" kill-server >/dev/null 2>&1 || true; fi
    rm -rf "$root/scrcpy"
    mv "$top" "$root/scrcpy"
    printf '%s\n' "$ver" > "$root/scrcpy/VERSION"
    if [ "$os" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
      xattr -dr com.apple.quarantine "$root/scrcpy" 2>/dev/null || true
    fi
    ok "Installed scrcpy $ver to $root/scrcpy"
  fi

  # --- CLI --------------------------------------------------------------------
  if [ -n "${DEX_SOURCE_DIR:-}" ]; then
    cp "$DEX_SOURCE_DIR/bin/dex" "$tmp/dex" || die "Cannot read $DEX_SOURCE_DIR/bin/dex"
  else
    fetch "$raw/bin/dex" "$tmp/dex" || die "Download failed: $raw/bin/dex"
  fi
  chmod 755 "$tmp/dex"
  mv -f "$tmp/dex" "$bindir/dex"
  ok "Installed $bindir/dex"

  # --- PATH ---------------------------------------------------------------------
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    # Only touch shells that are in use: ~/.profile always, ~/.zshrc on macOS (default shell).
    case "$rc" in
      */.profile) ;;
      */.zshrc) [ -f "$rc" ] || [ "$os" = "Darwin" ] || continue ;;
      *) [ -f "$rc" ] || continue ;;
    esac
    if ! grep -qs "$marker\$" "$rc"; then
      # shellcheck disable=SC2016
      printf 'export PATH="$HOME/.local/bin:$PATH" %s\n' "$marker" >> "$rc"
    fi
  done

  # --- launcher -------------------------------------------------------------------
  if [ "${DEX_NO_SHORTCUT:-0}" != "1" ]; then
    if [ "$os" = "Linux" ]; then
      local appdir="$HOME/.local/share/applications"
      mkdir -p "$appdir"
      # Graphical launcher when a dialog tool exists (zenity/kdialog), terminal menu otherwise.
      local gui_exec="\"$bindir/dex\"" gui_term=true
      if command -v zenity >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1; then gui_exec="\"$bindir/dex\" gui"; gui_term=false; fi
      cat > "$appdir/galaxy-dex.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Galaxy DeX
Comment=Samsung DeX in a window (scrcpy)
Exec=$gui_exec
Icon=$root/scrcpy/scrcpy.png
Terminal=$gui_term
Categories=Utility;
Actions=menu;
[Desktop Action menu]
Name=Terminal menu
Exec="$bindir/dex"
EOF
      ok "Added launcher: Galaxy DeX"
    else
      mkdir -p "$HOME/Applications"
      cat > "$HOME/Applications/Galaxy DeX.command" <<EOF
#!/bin/bash
export PATH="\$HOME/.local/bin:\$PATH"
dex gui
rc=\$?
if [ \$rc -ne 0 ]; then
  echo
  read -r -p "Press Enter to close..." _ || true
fi
exit \$rc
EOF
      chmod +x "$HOME/Applications/Galaxy DeX.command"
      ok "Added launcher: ~/Applications/Galaxy DeX.command"
    fi
  fi

  # --- Linux USB permissions ---------------------------------------------------------
  if [ "$os" = "Linux" ] && ! grep -qs 'uaccess\|plugdev' /etc/udev/rules.d/*android* /lib/udev/rules.d/*android* /usr/lib/udev/rules.d/*android*; then
    say ""
    say "${c_dim}USB on Linux may need an udev rule (Wi-Fi works without it):${c_off}"
    say "${c_dim}  sudo apt install android-sdk-platform-tools-common${c_off}"
  fi

  # --- done -------------------------------------------------------------------------
  say ""
  ok "Galaxy DeX is ready (scrcpy $ver)."
  case ":$PATH:" in
    *":$bindir:"*) say "Start it with:  dex" ;;
    *) say "Open a new terminal (or run: export PATH=\"\$HOME/.local/bin:\$PATH\"), then start it with:  dex" ;;
  esac
  say ""
  say "First-time phone checklist:"
  say "  1. Settings > About phone > Software information > tap Build number 7 times."
  say "  2. Settings > Developer options > USB debugging ON (cable) and/or Wireless debugging ON (Wi-Fi)."
  say "  3. Connect: plug in USB and accept \"Allow USB debugging\", or run: dex pair"
  say "  4. Run: dex keyboard   (set the physical keyboard layout to Turkish Q, once)"
  say "  5. Run: dex            (menu: press 1 for DeX; resize the window freely, F11 = fullscreen)"
  say "${c_dim}Needs One UI 8+ on the phone. Check with: dex doctor${c_off}"
}

main "$@"
