# GNU-style arguments are intentionally parsed from $args.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:root = if ($env:DEX_HOME) { $env:DEX_HOME } else { Join-Path $env:LOCALAPPDATA 'dex' }
$script:configDir = if ($env:DEX_CONFIG_DIR) { $env:DEX_CONFIG_DIR } else { Join-Path $env:APPDATA 'dex' }
$script:configFile = Join-Path $script:configDir 'config'
$script:adb = if ($env:DEX_ADB) { $env:DEX_ADB } else { Join-Path $script:root 'scrcpy/adb.exe' }
$script:scrcpy = if ($env:DEX_SCRCPY) { $env:DEX_SCRCPY } else { Join-Path $script:root 'scrcpy/scrcpy.exe' }
$script:config = @{}
if (Test-Path $script:configFile) {
    foreach ($line in Get-Content $script:configFile) {
        if ($line -match '^\s*([A-Z_]+)=(.*)$') { $script:config[$Matches[1]] = $Matches[2].Trim().Trim('"') }
    }
}
# Script state (phone selection, saved phone settings, menu state).
$script:serial = ''; $script:transport = ''; $script:usbList = @(); $script:tcpList = @(); $script:unauth = @()
$script:savedFf = ''; $script:savedBri = ''; $script:savedBriMode = ''; $script:lastConnectMsg = ''
$script:tuiSeen = ''; $script:tuiModel = ''; $script:tuiMsg = @('', 'DarkGray'); $script:scrcpyVer = ''
$script:menuBottom = 0; $script:col = 0; $script:frameW = 80
$script:savedDesktop = ''; $script:debugLog = ''; $script:logcatProcess = $null
$script:overlayId = ''
$script:adbExit = 0
$script:opt = @{ Mode = 'auto'; Res = ''; Dpi = ''; Screen = ''; Fullscreen = ''; Freeform = ''; Mouse = ''; Display = ''; Debug = $false; Raw = @() }
# Box drawing and marks need a UTF-8 console; fall back to ASCII otherwise.
$utf8 = $false
try { $utf8 = ([Console]::OutputEncoding.CodePage -eq 65001) } catch { Write-Verbose 'No console encoding.' }
if ($utf8) {
    $script:bx = @{ TL = [string][char]0x256D; TR = [string][char]0x256E; BL = [string][char]0x2570; BR = [string][char]0x256F
        H = [string][char]0x2500; V = [string][char]0x2502; ML = [string][char]0x251C; MR = [string][char]0x2524; Arrow = [string][char]0x203A; Dot = [string][char]0x00B7 }
    $script:okMark = [string][char]0x2713; $script:errMark = [string][char]0x2717
} else {
    $script:bx = @{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|'; ML = '+'; MR = '+'; Arrow = '>'; Dot = '-' }
    $script:okMark = 'OK'; $script:errMark = 'x'
}
# Windows Terminal and modern console hosts support ANSI bold; legacy hosts retain colors.
$script:vtBold = $false
try { $script:vtBold = [bool]$Host.UI.SupportsVirtualTerminal } catch { Write-Verbose 'No terminal styling support.' }
$script:boxW = 58
$script:banner = @'
           _                   _
  ___ _ __| | ____ _        __| | _____  __
 / _ \ '__| |/ / _` |_____ / _` |/ _ \ \/ /
|  __/ |  |   < (_| |_____| (_| |  __/>  <
 \___|_|  |_|\_\__,_|      \__,_|\___/_/\_\
'@
function Write-Ok([string]$Message) { Write-Host "$($script:okMark) $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "! $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "$($script:errMark) $Message" -ForegroundColor Red }
function Get-Cfg([string]$Key) {
    if ($script:config.ContainsKey($Key)) { return [string]$script:config[$Key] }
    return ''
}
function Save-ConfigValue([string]$Key, [string]$Value) {
    $script:config[$Key] = $Value
    $lines = @()
    $found = $false
    if (Test-Path $script:configFile) {
        foreach ($line in Get-Content $script:configFile) {
            if ($line -match ('^\s*' + [regex]::Escape($Key) + '=')) {
                if (!$found) { $lines += "$Key=$Value"; $found = $true }
            } else { $lines += $line }
        }
    }
    if (!$found) { $lines += "$Key=$Value" }
    New-Item -ItemType Directory -Force -Path (Split-Path $script:configFile) | Out-Null
    $tempConfig = "$($script:configFile).$([guid]::NewGuid().ToString()).tmp"
    try { Set-Content -LiteralPath $tempConfig -Value $lines -Encoding UTF8; Move-Item -LiteralPath $tempConfig -Destination $script:configFile -Force }
    finally { if (Test-Path $tempConfig) { Remove-Item -LiteralPath $tempConfig -Force } }
}
function Get-ExitCode($Value) {
    $items = @($Value)
    if ($items.Count -gt 0 -and $items[$items.Count - 1] -is [int]) { return $items[$items.Count - 1] }
    return 0
}
function Show-Help {
    $text = @'
dex - Samsung DeX in a window on your PC

Usage: dex                       interactive menu (pick 1, 2, 3 ...)
       dex [command] [options] [-- extra scrcpy args]

Commands:
  dex code           start DeX, profile "code" (crisp text, coding, browser)
  dex school         start DeX, profile "school" (denser, Word/Excel side by side)
  dex movie          start DeX, profile "movie" (high bitrate, H.265)
  dex mirror         plain phone-screen mirror (no virtual display)
  dex pair           wireless pairing without a cable (once per PC; dex remembers the phone)
  dex connect [ip:port]  connect over Wi-Fi (no arg: auto-discover / remembered phone)
  dex wifi           switch a USB-connected phone to Wi-Fi
  dex wake           wake the phone / unfreeze a stuck DeX window
  dex keyboard       open phone keyboard settings (pick Turkish Q)
  dex doctor         show versions, devices and phone info
  dex debug          start DeX (code) and save a phone log for bug reports
  dex update         re-run the installer (latest scripts)
  dex uninstall      remove everything dex installed
  dex help           this text

Options (start commands):
  --res WxH          initial window size (default: 80% of your screen)
  --dpi N            DeX density (code 160, school 140, movie 160)
  --usb / --wifi     force the transport
  --screen on|dim|off  phone panel while DeX runs (default: on; see below)
  --screen-off       same as --screen off
  --fullscreen       start fullscreen at your monitor's resolution (native DeX feel)
  --no-freeform      skip the One UI 8.5+/9 windowing fix
  --display auto|overlay|virtual
                     overlay (default on One UI 8.5+/9): DeX runs on a system overlay
                     display, the only kind Android 16 QPR2+/17 gives real desktop windows
                     (title bars, drag, resize, minimize). Android shows a small preview of
                     it on the phone screen. virtual: scrcpy's own display (resizes with the
                     window, but on One UI 8.5+/9 apps have no title bars).
  --mouse uhid|sdk   uhid (default on Android 15+): real HID mouse on the DeX display,
                     DeX title bars drag like with a plugged-in mouse (Alt releases the
                     PC pointer). sdk: injected touch-style clicks, pointer not captured.
  --debug            save the phone log of this session to the config folder
  --                 pass everything after it to scrcpy

Phone screen: "on" is the safe default (DeX never freezes). "dim" keeps the panel
technically on but at minimum brightness and restores it afterwards. "off" turns the
panel off; on some Galaxy phones DeX then stops responding -> run: dex wake

Config: {CONFIG}
  DEX_SCREEN, DEX_FULLSCREEN, DEX_RES, DEX_DPI, DEX_SHORTCUT_MOD, DEX_EXTRA_ARGS,
  DEX_FREEFORM, DEX_FREEFORM_SUPPORT (0|1, unset = leave the phone's value alone),
  DEX_DISPLAY (auto|overlay|virtual), DEX_MOUSE (uhid|sdk),
  DEX_FORCE_DESKTOP (1 = also set force_desktop_mode_on_external_displays while DeX runs),
  DEX_LAST_ENDPOINT, DEX_LAST_IP, DEX_PHONE_NAME, DEX_PHONE_SERIAL (remembered phone)
'@
    $text = $text.Replace('{CONFIG}', $script:configFile)
    Write-Host $text
}
function Test-ToolInstallation {
    $env:ADB = $script:adb
    if (!(Test-Path $script:adb) -or !(Test-Path $script:scrcpy)) { throw 'Bundled adb/scrcpy is missing. Re-run the installer (dex update).' }
}
# --- adb helpers ----------------------------------------------------------------
function Invoke-Adb([string[]]$Arguments, [switch]$NoThrow) {
    # Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $result = @(& $script:adb @Arguments 2>&1 | ForEach-Object { "$_" })
    $script:adbExit = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -and !$NoThrow) { throw "adb failed: $($result -join ' ')" }
    return $result
}
function Invoke-Phone([string[]]$Cmd) {
    try { $lines = @(Invoke-Adb -Arguments (@('-s', $script:serial, 'shell') + $Cmd) -NoThrow) } catch { return }
    foreach ($l in $lines) { $l.Replace("`r", '') }
}
function Get-PhoneValue([string[]]$Cmd) {
    $out = @(Invoke-Phone $Cmd)
    if ($out.Count -gt 0) { return ([string]$out[0]).Trim() }
    return ''
}
function Invoke-DeviceScan {
    $script:usbList = @(); $script:tcpList = @(); $script:unauth = @()
    foreach ($line in @(Invoke-Adb -Arguments @('devices', '-l') -NoThrow)) {
        if ($line -match '^(\S+)\s+(device|unauthorized)\b') {
            $s = $Matches[1]
            if ($Matches[2] -eq 'unauthorized') { $script:unauth += $s }
            elseif ($s -match ':' -or $s -match '_adb-tls-') { $script:tcpList += $s }
            else { $script:usbList += $s }
        }
    }
}
function Find-Endpoint {
    $first = ''; $remembered = Get-Cfg 'DEX_PHONE_SERIAL'
    foreach ($line in @(Invoke-Adb -Arguments @('mdns', 'services') -NoThrow)) {
        if ($line -match '^\s*(\S+)\s+_adb-tls-connect\._tcp\.?\s+(\S+:\d+)') {
            $instance = $Matches[1]; $endpoint = $Matches[2]
            if (!$first) { $first = $endpoint }
            if ($remembered -and $instance.Contains($remembered)) { return $endpoint }
        }
    }
    return $first
}
function Save-Endpoint([string]$Endpoint) {
    Save-ConfigValue 'DEX_LAST_ENDPOINT' $Endpoint
    Save-ConfigValue 'DEX_LAST_IP' ($Endpoint -replace ':[^:]*$', '')
}
function Get-RememberedPhone {
    $name = Get-Cfg 'DEX_PHONE_NAME'; $ip = Get-Cfg 'DEX_LAST_IP'
    if (!$name -and !$ip) { return '' }
    if (!$name) { $name = 'phone' }
    if ($ip) { return "$name (last at $ip)" }
    return $name
}
function Save-PhoneIdentity {
    $phoneSerial = Get-PhoneValue @('getprop', 'ro.serialno')
    if (!$phoneSerial -or $phoneSerial -eq (Get-Cfg 'DEX_PHONE_SERIAL')) { return }
    $name = Get-PhoneValue @('getprop', 'ro.product.marketname')
    if (!$name) { $name = Get-PhoneValue @('getprop', 'ro.product.model') }
    Save-ConfigValue 'DEX_PHONE_SERIAL' $phoneSerial
    if ($name) { Save-ConfigValue 'DEX_PHONE_NAME' $name }
}
# adb names a TCP device by its endpoint, so remember the phone just connected (not the first
# Wi-Fi device in the list).
function Sync-WifiPhone([string]$Endpoint = '') {
    if (!$Endpoint) { $Endpoint = Get-Cfg 'DEX_LAST_ENDPOINT' }
    if (!$Endpoint) { return }
    $script:serial = $Endpoint
    Save-PhoneIdentity
}
function Connect-RememberedPhone {
    $ip = Get-Cfg 'DEX_LAST_IP'
    if (!$ip -or $env:DEX_NO_TUI -eq '1' -or ![Environment]::UserInteractive) { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    Write-Host "Remembered phone: $(Get-RememberedPhone). The pairing is kept; only the port changes."
    Write-Host 'Phone > Developer options > Wireless debugging > "IP address & Port" (Enter = skip)'
    $endpoint = Read-Host 'Port or IP:port'
    if (!$endpoint) { return $false }
    if ($endpoint -notmatch ':') { $endpoint = "${ip}:$endpoint" }
    if (Test-Connect $endpoint) { return $true }
    Write-Warn "Could not connect to $endpoint."
    return $false
}
function Test-Connect([string]$Endpoint) {
    $text = @(Invoke-Adb -Arguments @('connect', $Endpoint) -NoThrow) -join ' '
    if ($text -match 'connected to') { Save-Endpoint $Endpoint; return $true }
    $script:lastConnectMsg = $text
    return $false
}
function Connect-Endpoint([string]$Endpoint) {
    if ($Endpoint -notmatch '^[^\s]+:\d+$') { throw 'Enter an endpoint in IP:port format.' }
    if (!(Test-Connect $Endpoint)) { throw $script:lastConnectMsg }
}
function Connect-DiscoveredEndpoint {
    $ep = Find-Endpoint
    if (!$ep) { return $false }
    Write-Host "Found phone via mDNS: $ep"
    return (Test-Connect $ep)
}
function Connect-Saved {
    $ep = Get-Cfg 'DEX_LAST_ENDPOINT'
    if (!$ep) { return $false }
    Write-Host "Trying last endpoint $ep ..."
    return (Test-Connect $ep)
}
function Show-WifiHint {
    Write-Host 'Could not pair/connect. Check:'
    Write-Host '  - Phone and PC are on the same Wi-Fi network.'
    Write-Host '  - School Wi-Fi may isolate clients: use Windows Settings > Mobile hotspot (phone joins PC), or a USB cable.'
    Write-Host '  - A phone hotspot does NOT work: Wireless debugging needs the phone to be a Wi-Fi client.'
}
function Show-NoDevice {
    if ($script:unauth.Count -gt 0) {
        Write-Err ('Phone {0} is unauthorized: accept the "Allow USB debugging" prompt on the phone, then retry.' -f $script:unauth[0])
    }
    Write-Err 'No phone found.'
    $remembered = Get-RememberedPhone
    if ($remembered) {
        Write-Host "Remembered: $remembered. It is already paired with this PC: no code needed."
        Write-Host '  1. Plug in the USB cable, or'
        Write-Host '  2. dex connect - type the current port from Wireless debugging ("IP address & Port").'
        Write-Host '     (Wireless debugging must be ON and the phone on the same Wi-Fi.)'
        Write-Host '  3. dex pair    - only if the phone forgot this PC (Wireless debugging > Paired devices).'
        return
    }
    Write-Host 'Options:'
    Write-Host '  1. Plug in the USB cable (and accept "Allow USB debugging" on the phone).'
    Write-Host '  2. dex pair   - pair wirelessly (Wireless debugging), no cable needed. Once per PC.'
    Write-Host '  3. dex wifi   - with the cable plugged in, switch the connection to Wi-Fi.'
    Write-Host 'USB not detected on Windows? Install the Samsung USB driver (needs admin) or use Wi-Fi: dex pair'
}
# Sets $script:serial / $script:transport (usb|wifi); returns 2 if there is no usable phone.
function Select-Device([string]$Mode) {
    $script:serial = ''; $script:transport = ''
    Invoke-DeviceScan
    if ($Mode -ne 'wifi' -and $script:usbList.Count -gt 0) {
        $script:serial = $script:usbList[0]; $script:transport = 'usb'
        if ($script:usbList.Count -gt 1) { Write-Host "Several USB devices; using $($script:serial)" }
        return 0
    }
    if ($Mode -eq 'usb') { Show-NoDevice; return 2 }
    if ($script:tcpList.Count -eq 0) {
        if ((Connect-DiscoveredEndpoint) -or (Connect-Saved) -or (Connect-RememberedPhone)) { Invoke-DeviceScan }
    }
    if ($script:tcpList.Count -gt 0) {
        $script:serial = $script:tcpList[0]; $script:transport = 'wifi'
        if ($script:tcpList.Count -gt 1) { Write-Host "Several Wi-Fi devices; using $($script:serial)" }
        return 0
    }
    Show-NoDevice
    return 2
}
# --- phone state ------------------------------------------------------------------
# One UI 8.5 / 9 (Android 16 QPR2+) no longer enables desktop windowing on app-created virtual
# displays: DeX starts, but every app opens fullscreen. The per-display windowing mode can be
# forced with a shell command (5 = WINDOWING_MODE_FREEFORM); One UI 8.0 does not need it.
function Enable-Freeform([string]$DisplayId) {
    Invoke-Adb -Arguments @('-s', $script:serial, 'shell', 'wm', 'set-display-windowing-mode', '-d', $DisplayId, '5') -NoThrow | Out-Null
    if ($script:adbExit -eq 0) {
        Write-Ok "Desktop windowing enabled on DeX display $DisplayId (apps open as movable windows)."
    } else {
        Write-Host "Display ${DisplayId}: windowing-mode command not available (One UI 8.0?), freeform should already be on." -ForegroundColor DarkGray
    }
}
function Get-Wakefulness {
    foreach ($l in @(Invoke-Phone @('dumpsys', 'power'))) {
        if ($l -match 'mWakefulness=([A-Za-z]+)') { return $Matches[1] }
    }
    return ''
}
# A sleeping/dozing phone never renders the new virtual display (nothing or a frozen frame).
function Invoke-WakePhone {
    if ((Get-Wakefulness) -in @('Asleep', 'Dozing')) {
        Write-Host 'Waking the phone...'
        Invoke-Phone @('input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
        Start-Sleep -Seconds 1
    }
    $inKeyguard = $false
    foreach ($l in @(Invoke-Phone @('dumpsys', 'window', 'policy'))) {
        if ($l -match 'KeyguardServiceDelegate') { $inKeyguard = $true }
        if ($inKeyguard -and $l -match 'showing=true') {
            Write-Warn 'The phone is locked. Unlock it, or DeX shows only the lock screen (Samsung also hides the dock while locked).'
            break
        }
    }
}
function Invoke-DimOn {
    $script:savedBri = Get-PhoneValue @('settings', 'get', 'system', 'screen_brightness')
    $script:savedBriMode = Get-PhoneValue @('settings', 'get', 'system', 'screen_brightness_mode')
    Invoke-Phone @('settings', 'put', 'system', 'screen_brightness_mode', '0') | Out-Null
    Invoke-Phone @('settings', 'put', 'system', 'screen_brightness', '0') | Out-Null
    Write-Host 'Phone screen dimmed (restored when DeX closes).' -ForegroundColor DarkGray
}
# The freeform developer option is restored on exit. Leave it untouched on One UI 8.5+/9
# unless explicitly configured; older builds may need it enabled.
function Get-WantedFreeformSupport {
    $v = Get-Cfg 'DEX_FREEFORM_SUPPORT'
    if ($v -in @('0', '1')) { return $v }
    $v = Get-PhoneValue @('getprop', 'ro.build.version.oneui')
    if ($v -match '^\d+$' -and [int]$v -ge 80500) { return '' }
    return '1'
}
function Invoke-FreeformSupport([string]$Value) {
    if (!$Value) { return }
    $script:savedFf = ''
    $v = Get-PhoneValue @('settings', 'get', 'global', 'enable_freeform_support')
    if ($v -notmatch '^(null|\d+)$' -or $v -eq $Value) { return } # unreadable, or already right
    if ($v -eq 'null' -and $Value -eq '0') { return } # unset means off
    $script:savedFf = $v
    Invoke-Phone @('settings', 'put', 'global', 'enable_freeform_support', $Value) | Out-Null
    if ($Value -eq '0') {
        Write-Host 'Freeform developer option off while DeX runs (it breaks window dragging on One UI 8.5+).' -ForegroundColor DarkGray
    }
}
function Get-WantedMouse {
    $value = $script:opt.Mouse
    if (!$value) { $value = Get-Cfg 'DEX_MOUSE' }
    if ($value -in @('uhid', 'sdk')) { return $value }
    $sdk = Get-PhoneValue @('getprop', 'ro.build.version.sdk')
    if ($sdk -match '^\d+$' -and [int]$sdk -ge 35) { return 'uhid' }
    return 'sdk'
}
function Get-WantedDisplay {
    $value = $script:opt.Display
    if (!$value) { $value = Get-Cfg 'DEX_DISPLAY' }
    if ($value -in @('overlay', 'virtual')) { return $value }
    $ui = Get-PhoneValue @('getprop', 'ro.build.version.oneui')
    if ($ui -match '^\d+$') {
        if ([int]$ui -ge 80500) { return 'overlay' }
        return 'virtual'
    }
    $sdk = Get-PhoneValue @('getprop', 'ro.build.version.sdk')
    if ($sdk -match '^\d+$' -and [int]$sdk -ge 37) { return 'overlay' }
    return 'virtual'
}
# System overlay displays receive desktop decorations on One UI 8.5+/9.
function Invoke-OverlayCreate([string]$Resolution, [string]$Dpi) {
    Invoke-Phone @('settings', 'put', 'global', 'overlay_display_devices', "$Resolution/$Dpi") | Out-Null
    for ($i = 0; $i -lt 40; $i++) {
        foreach ($line in @(Invoke-Phone @('dumpsys', 'display'))) {
            if ($line -match 'type OVERLAY' -and $line -match 'displayId (\d+),') {
                $script:overlayId = $Matches[1]
                return $true
            }
        }
        Start-Sleep -Milliseconds 250
    }
    Invoke-Phone @('settings', 'delete', 'global', 'overlay_display_devices') | Out-Null
    return $false
}
function Invoke-OverlayDestroy {
    if (!$script:overlayId) { return }
    Invoke-Phone @('settings', 'delete', 'global', 'overlay_display_devices') | Out-Null
    $script:overlayId = ''
}
function Invoke-ForceDesktop {
    if ((Get-Cfg 'DEX_FORCE_DESKTOP') -ne '1') { return }
    $value = Get-PhoneValue @('settings', 'get', 'global', 'force_desktop_mode_on_external_displays')
    if (!$value -or $value -eq '1') { return }
    $script:savedDesktop = $value
    Invoke-Phone @('settings', 'put', 'global', 'force_desktop_mode_on_external_displays', '1') | Out-Null
    Write-Host 'force_desktop_mode_on_external_displays=1 while DeX runs (DEX_FORCE_DESKTOP).' -ForegroundColor DarkGray
}
function Invoke-PhoneRestore {
    if ($script:savedBri -match '^\d+$') { Invoke-Phone @('settings', 'put', 'system', 'screen_brightness', $script:savedBri) | Out-Null }
    if ($script:savedBriMode -match '^\d+$') { Invoke-Phone @('settings', 'put', 'system', 'screen_brightness_mode', $script:savedBriMode) | Out-Null }
    if ($script:savedFf -eq 'null') { Invoke-Phone @('settings', 'delete', 'global', 'enable_freeform_support') | Out-Null }
    elseif ($script:savedFf) { Invoke-Phone @('settings', 'put', 'global', 'enable_freeform_support', $script:savedFf) | Out-Null }
    if ($script:savedDesktop -eq 'null') { Invoke-Phone @('settings', 'delete', 'global', 'force_desktop_mode_on_external_displays') | Out-Null }
    elseif ($script:savedDesktop) { Invoke-Phone @('settings', 'put', 'global', 'force_desktop_mode_on_external_displays', $script:savedDesktop) | Out-Null }
    Invoke-OverlayDestroy
    $script:savedDesktop = ''
    $script:savedBri = ''; $script:savedBriMode = ''; $script:savedFf = ''
}
function Get-OneUi {
    $v = Get-PhoneValue @('getprop', 'ro.build.version.oneui')
    if ($v -match '^\d+$') {
        $n = [int]$v
        return ('{0}.{1}' -f [math]::Floor($n / 10000), [math]::Floor(($n % 10000) / 100))
    }
    return ''
}
function Get-ScrcpyLine {
    $ErrorActionPreference = 'Continue'
    try {
        $l = @(& $script:scrcpy --version 2>&1 | ForEach-Object { "$_" })
        if ($l.Count -gt 0) { return $l[0] }
    } catch { Write-Verbose 'scrcpy is not runnable.' }
    return 'not runnable'
}
function Get-DefaultResolution([int]$Percent) {
    $w = 0; $h = 0
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $rect = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($Percent -ge 100) { $rect = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds }
        $w = [int]([math]::Floor($rect.Width * $Percent / 100 / 8) * 8)
        $h = [int]([math]::Floor($rect.Height * $Percent / 100 / 8) * 8)
    } catch { Write-Verbose 'Screen detection unavailable.' }
    if ($w -ge 640 -and $h -ge 480) { return "${w}x${h}" }
    if ($Percent -ge 100) { return '1920x1080' }
    return '1600x900'
}
# Runs scrcpy with its output streamed live and watched line by line; applies the freeform fix as
# soon as the virtual display exists. Returns scrcpy's real exit code.
function Invoke-Scrcpy([string[]]$ScrcpyArgs, [bool]$Watch) {
    $ErrorActionPreference = 'Continue'
    & $script:scrcpy @ScrcpyArgs 2>&1 | ForEach-Object {
        $text = "$_"
        Write-Host $text
        if ($Watch -and $text -match 'New display:.*\(id=(\d+)\)') {
            $displayId = $Matches[1]
            Enable-Freeform $displayId
            if ($script:debugLog) {
                Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Value "`n==== dumpsys window displays (display $displayId, after the freeform fix) ====" -Encoding UTF8
                Invoke-Phone @('dumpsys', 'window', 'displays') | Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Encoding UTF8
            }
        }
    }
    return $LASTEXITCODE
}
# Start-Process cannot append redirected output on Windows PowerShell 5.1. Capture
# logcat in a sidecar while running, then merge it after the header when it stops.
function Invoke-DebugStart([string[]]$ScrcpyArgs) {
    New-Item -ItemType Directory -Force -Path $script:configDir | Out-Null
    $script:debugLog = Join-Path $script:configDir ("debug-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    @(
        "dex debug $(Get-Date)"
        "scrcpy: $($ScrcpyArgs -join ' ')"
        "phone: $(Get-PhoneValue @('getprop', 'ro.product.model')) One UI $(Get-PhoneValue @('getprop', 'ro.build.version.oneui')) SDK $(Get-PhoneValue @('getprop', 'ro.build.version.sdk'))"
        "settings: freeform_support=$(Get-PhoneValue @('settings', 'get', 'global', 'enable_freeform_support')) force_desktop=$(Get-PhoneValue @('settings', 'get', 'global', 'force_desktop_mode_on_external_displays'))"
    ) | Set-Content -LiteralPath $script:debugLog -Encoding UTF8
    if ($script:overlayId) {
        Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Value "==== dumpsys window displays (overlay display $($script:overlayId), before scrcpy) ====" -Encoding UTF8
        Invoke-Phone @('dumpsys', 'window', 'displays') | Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Encoding UTF8
    }
    Invoke-Adb -Arguments @('-s', $script:serial, 'logcat', '-c') -NoThrow | Out-Null
    $script:logcatProcess = Start-Process -FilePath $script:adb -ArgumentList @('-s', $script:serial, 'logcat', '-v', 'threadtime', '*:D') -NoNewWindow -PassThru -RedirectStandardOutput "$($script:debugLog).logcat" -RedirectStandardError "$($script:debugLog).stderr"
    Write-Host "Debug log: $($script:debugLog) (open an app, drag its title bar, press its buttons, then close DeX)" -ForegroundColor Yellow
}
function Invoke-DebugStop {
    if (!$script:debugLog) { return }
    try {
        Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Value "`n==== dumpsys window windows (at exit) ====" -Encoding UTF8
        Invoke-Phone @('dumpsys', 'window', 'windows') | Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Encoding UTF8
        Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Value "`n==== dumpsys activity activities (at exit) ====" -Encoding UTF8
        Invoke-Phone @('dumpsys', 'activity', 'activities') | Add-Content -LiteralPath "$($script:debugLog).dumpsys" -Encoding UTF8
    } finally {
        if ($null -ne $script:logcatProcess) {
            if (!$script:logcatProcess.HasExited) { Stop-Process -InputObject $script:logcatProcess -ErrorAction SilentlyContinue }
            $script:logcatProcess.WaitForExit()
            $script:logcatProcess.Dispose()
            $script:logcatProcess = $null
        }
        foreach ($suffix in @('.logcat', '.stderr')) {
            $capture = "$($script:debugLog)$suffix"
            if (Test-Path -LiteralPath $capture) {
                Get-Content -LiteralPath $capture -Encoding UTF8 -ReadCount 2000 | ForEach-Object { $_ } | Add-Content -LiteralPath $script:debugLog -Encoding UTF8
                Remove-Item -LiteralPath $capture -Force
            }
        }
        $filtered = @(Get-Content -LiteralPath $script:debugLog -Encoding UTF8 | Where-Object { $_ -match 'ShellDesktopMode|DesktopMode|wmshell|FATAL|AndroidRuntime|DexCaption|Caption' })
        Set-Content -LiteralPath "$($script:debugLog).filtered" -Value $filtered -Encoding UTF8
        Write-Ok "Debug log saved: $($script:debugLog) (+ .dumpsys, .filtered). Send these files with your bug report."
        $script:debugLog = ''
    }
}
# --- start ------------------------------------------------------------------------
function Invoke-DexStart([string]$Kind) {
    Test-ToolInstallation
    $rc = Select-Device $script:opt.Mode
    if ($rc -ne 0) { return $rc }
    if (!(Get-Cfg 'DEX_KEYBOARD_HINT_SHOWN')) {
        Write-Host "Tip: for the Turkish Q layout run 'dex keyboard' once (physical keyboard settings on the phone)."
        Save-ConfigValue 'DEX_KEYBOARD_HINT_SHOWN' '1'
    }
    $codec = 'h264'; $extraProfile = @()
    switch ($Kind) {
        'code' { $bitrate = 16 }
        'school' { $bitrate = 12 }
        'movie' {
            $bitrate = 24; $codec = 'h265'; $extraProfile = @('--audio-buffer=80')
            Write-Host 'Netflix / Disney+ / Prime use DRM: video stays black inside a PC window (Android'
            Write-Host 'blocks capture of protected content). For DRM content use a USB-C to HDMI cable/hub to a'
            Write-Host "monitor/TV (real DeX), Wireless DeX to a smart TV, or the streaming site in the PC's"
            Write-Host 'browser. YouTube, local files, Plex/Jellyfin work fine here.'
        }
        default { $bitrate = 12 }
    }
    if ($script:transport -eq 'wifi') { $bitrate = [int]($bitrate / 2) }
    $fullscreen = $script:opt.Fullscreen
    if (!$fullscreen) { $fullscreen = Get-Cfg 'DEX_FULLSCREEN' }
    $res = $script:opt.Res
    if (!$res) { $res = Get-Cfg 'DEX_RES' }
    if (!$res) { $res = if ($fullscreen -eq '1') { Get-DefaultResolution 100 } else { Get-DefaultResolution 80 } }
    $dpi = $script:opt.Dpi
    if (!$dpi) { $dpi = Get-Cfg 'DEX_DPI' }
    if (!$dpi) { $dpi = if ($Kind -eq 'school') { '140' } else { '160' } }
    $mod = Get-Cfg 'DEX_SHORTCUT_MOD'
    if (!$mod) { $mod = 'lalt' }
    $screen = $script:opt.Screen
    if (!$screen) { $screen = Get-Cfg 'DEX_SCREEN' }
    if ($screen -notin @('on', 'dim', 'off')) { $screen = 'on' }
    $freeform = $script:opt.Freeform
    if (!$freeform) { $freeform = Get-Cfg 'DEX_FREEFORM' }
    $watch = ($freeform -ne '0' -and $Kind -ne 'mirror') # mirror has no virtual display to fix

    $mouse = Get-WantedMouse
    $display = 'virtual'
    if ($Kind -ne 'mirror') { $display = Get-WantedDisplay }
    $scrcpyArgs = @('-s', $script:serial)
    if ($Kind -ne 'mirror') {
        if ($display -eq 'overlay') { $scrcpyArgs += '--display-id=OVERLAY' }
        else { $scrcpyArgs += @("--new-display=$res/$dpi", '--flex-display', '--no-vd-destroy-content') }
        $scrcpyArgs += @('--keyboard=uhid', "--mouse=$mouse", '--mouse-bind=++++:bhsn')
    }
    $scrcpyArgs += @("--window-title=Galaxy DeX ($Kind)", "--shortcut-mod=$mod")
    # --keep-active keeps the phone awake on USB and Wi-Fi; --stay-awake only works when plugged in.
    $scrcpyArgs += @('--keep-active', '--disable-screensaver', '--max-fps=60', "--video-bit-rate=${bitrate}M")
    if ($script:transport -eq 'usb') { $scrcpyArgs += '--stay-awake' }
    if ($script:transport -eq 'wifi') { $scrcpyArgs += '--video-buffer=50' } # absorbs Wi-Fi jitter
    if ($Kind -eq 'mirror') { $scrcpyArgs += '--keyboard=uhid' } else { $scrcpyArgs += @("--video-codec=$codec") + $extraProfile }
    if ($screen -eq 'off') { $scrcpyArgs += '--turn-screen-off' }
    if ($fullscreen -eq '1') { $scrcpyArgs += '--fullscreen' }
    $cfgExtra = Get-Cfg 'DEX_EXTRA_ARGS'
    if ($cfgExtra) {
        # Tokenize quoted arguments without evaluating config as PowerShell code.
        foreach ($match in [regex]::Matches($cfgExtra, '(?:[^\s"'']+|"[^"]*"|''[^'']*'')+')) {
            $scrcpyArgs += ($match.Value -replace '"([^"]*)"|''([^'']*)''', '$1$2')
        }
    }
    $scrcpyArgs += @($script:opt.Raw)
    if ($env:DEX_DRY_RUN -eq '1') { Write-Host ('scrcpy ' + ($scrcpyArgs -join ' ')); return 0 }

    Save-ConfigValue 'DEX_LAST_PROFILE' $Kind
    Save-PhoneIdentity
    Invoke-WakePhone
    try {
        if ($watch) { Invoke-FreeformSupport (Get-WantedFreeformSupport); Invoke-ForceDesktop }
        if ($screen -eq 'dim') { Invoke-DimOn }
        if ($display -eq 'overlay') {
            if (Invoke-OverlayCreate $res $dpi) {
                Write-Ok "Overlay display $($script:overlayId) created ($res @ $dpi dpi): DeX runs on it like on an external monitor."
                Write-Host 'Android shows a small preview of it on the phone screen; ignore it. Size is fixed for this session (r = change).' -ForegroundColor DarkGray
                if ($watch) { Enable-Freeform $script:overlayId }
                $scrcpyArgs = @($scrcpyArgs | ForEach-Object {
                    if ($_ -eq '--display-id=OVERLAY') { "--display-id=$($script:overlayId)" } else { $_ }
                })
            } else {
                Write-Warn "Could not create the overlay display; falling back to scrcpy's virtual display (no window title bars on One UI 8.5+)."
                $display = 'virtual'
                $scrcpyArgs = @($scrcpyArgs | ForEach-Object {
                    if ($_ -eq '--display-id=OVERLAY') { "--new-display=$res/$dpi"; '--flex-display'; '--no-vd-destroy-content' } else { $_ }
                })
            }
        }
        if ($script:opt.Debug) { Invoke-DebugStart $scrcpyArgs }
        Write-Host "Starting Galaxy DeX ($Kind, $($script:transport), $res @ $dpi dpi, screen: $screen, mouse: $mouse, display: $display)..."
        Write-Host 'Resize the window freely. F11 = fullscreen, Alt+q quits. Frozen? Run: dex wake' -ForegroundColor DarkGray
        if ($Kind -ne 'mirror' -and $mouse -eq 'uhid') {
            Write-Host 'The DeX window captures the mouse (real HID mouse on the phone). Press Alt to give it back to the PC, click the window to capture again.' -ForegroundColor DarkGray
        }
        $code = Get-ExitCode (Invoke-Scrcpy $scrcpyArgs $watch)
    } finally { try { Invoke-PhoneRestore } finally { Invoke-DebugStop } } # also runs on Ctrl+C
    if ($code -eq 0) { Write-Ok 'DeX closed. Your apps moved back to the phone.' }
    elseif ($code -eq 2) { Write-Warn 'The phone disconnected (cable unplugged, Wi-Fi dropped or the phone slept).' }
    else { Write-Err "scrcpy exited with code $code." }
    return $code
}
# --- other commands ---------------------------------------------------------------
function Invoke-Pair {
    Test-ToolInstallation
    $remembered = Get-RememberedPhone
    if ($remembered) {
        Write-Host "Remembered phone: $remembered. Pairing is only needed once per PC; checking if it is reachable..."
        if ((Connect-DiscoveredEndpoint) -or (Connect-Saved)) { Sync-WifiPhone; Write-Ok 'Already paired and connected. Run: dex'; return 0 }
        Write-Host 'Not reachable. If Wireless debugging is on and only the port changed, use: dex connect'
        Write-Host 'Continue to pair again (needed if the phone forgot this PC, e.g. after a PC reset).'
    }
    Write-Host 'Pair without a cable (once per PC):'
    Write-Host '  Phone > Settings > Developer options > Wireless debugging ON'
    Write-Host '  > "Pair device with pairing code".'
    try {
        $pairEndpoint = Read-Host 'Pairing IP:port (shown in the dialog)'
        $pairCode = Read-Host '6-digit pairing code'
        if ($pairEndpoint -notmatch '^[^\s]+:\d+$' -or $pairCode -notmatch '^\d{6}$') { throw 'Enter IP:port and a 6-digit pairing code.' }
        foreach ($l in @(Invoke-Adb -Arguments @('pair', $pairEndpoint, $pairCode))) { Write-Host $l }
        Write-Host 'Paired. Now the connect port (Wireless debugging main screen: "IP address & Port").'
        if (!(Connect-DiscoveredEndpoint)) { Connect-Endpoint (Read-Host 'Connect IP:port') }
        Sync-WifiPhone
        Write-Ok 'Connected and remembered. Next time: just run dex (or press c if the port changed). Run: dex'
        return 0
    } catch { Show-WifiHint; throw }
}
function Invoke-ConnectCmd([string]$Endpoint) {
    Test-ToolInstallation
    try {
        if (!$Endpoint) {
            if (Connect-DiscoveredEndpoint) { Sync-WifiPhone; Write-Ok 'Connected.'; return 0 }
            if (Connect-Saved) { Sync-WifiPhone; Write-Ok "Connected to $(Get-Cfg 'DEX_LAST_ENDPOINT')."; return 0 }
            if (Get-Cfg 'DEX_LAST_IP') {
                Write-Host "Remembered phone: $(Get-RememberedPhone). No pairing code needed, only the current port."
                $Endpoint = Read-Host 'Port or IP:port (Wireless debugging > "IP address & Port")'
            } else { $Endpoint = Read-Host 'Phone IP:port (Wireless debugging screen)' }
        }
        if (!$Endpoint) { throw 'No endpoint given. Try: dex pair' }
        if ($Endpoint -notmatch ':') {
            if ($Endpoint -match '^\d+$') {
                $ip = Get-Cfg 'DEX_LAST_IP'
                if (!$ip) { throw 'Only a port given but no remembered phone. Use IP:port.' }
                $Endpoint = "${ip}:$Endpoint"
            } else { $Endpoint = "${Endpoint}:5555" }
        }
        Connect-Endpoint $Endpoint
        Sync-WifiPhone
        Write-Ok "Connected to $Endpoint. Run: dex"
        return 0
    } catch { Show-WifiHint; throw }
}
function Invoke-Wifi {
    Test-ToolInstallation
    Invoke-DeviceScan
    if ($script:usbList.Count -eq 0) {
        if ($script:unauth.Count -gt 0) { Show-NoDevice } else { Write-Err 'Plug the phone in with USB first.' }
        return 2
    }
    $s = $script:usbList[0]
    $address = @(Invoke-Adb -Arguments @('-s', $s, 'shell', 'ip', '-f', 'inet', 'addr', 'show', 'wlan0') -NoThrow) -join ' '
    if ($address -match '\binet\s+(\d+\.\d+\.\d+\.\d+)/') { $endpoint = $Matches[1] + ':5555' }
    else { Write-Err "Could not read the phone's Wi-Fi IP. Is Wi-Fi on?"; return 1 }
    Invoke-Adb -Arguments @('-s', $s, 'tcpip', '5555') | Out-Null
    Start-Sleep -Seconds 2
    Connect-Endpoint $endpoint
    Sync-WifiPhone
    Write-Ok "Connected over Wi-Fi ($endpoint). You can unplug the cable (works until the phone reboots)."
    return 0
}
function Invoke-Wake {
    Test-ToolInstallation
    $rc = Select-Device $script:opt.Mode
    if ($rc -ne 0) { return $rc }
    # -d 0 targets the phone panel (Android 14+ needs the display id), the second call is the fallback.
    Invoke-Phone @('input', '-d', '0', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Phone @('input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Write-Ok 'Wake-up sent. If the DeX window is still frozen: unlock the phone, or press Alt+Shift+r in the window.'
    return 0
}
function Invoke-Keyboard {
    Test-ToolInstallation
    $rc = Select-Device $script:opt.Mode
    if ($rc -ne 0) { return $rc }
    Invoke-Adb -Arguments @('-s', $script:serial, 'shell', 'am', 'start', '-a', 'android.settings.HARD_KEYBOARD_SETTINGS') | Out-Null
    Write-Ok 'Opened the keyboard settings on the phone. Pick Turkish Q as the layout.'
    return 0
}
function Invoke-Doctor {
    Test-ToolInstallation
    Write-Host "scrcpy: $(Get-ScrcpyLine)"
    $versionLine = @(Invoke-Adb -Arguments @('version') -NoThrow)
    Write-Host ('adb:    ' + $(if ($versionLine.Count -gt 0) { $versionLine[0] } else { 'not runnable' }))
    Write-Host 'devices:'
    foreach ($l in @(Invoke-Adb -Arguments @('devices', '-l') -NoThrow)) { Write-Host "  $l" }
    Invoke-DeviceScan
    $all = @($script:usbList) + @($script:tcpList)
    if ($all.Count -eq 0) { Show-NoDevice; return 2 }
    $script:serial = $all[0]
    $model = Get-PhoneValue @('getprop', 'ro.product.model')
    $sdk = Get-PhoneValue @('getprop', 'ro.build.version.sdk')
    if (!$model) { $model = 'unknown' }
    if (!$sdk) { $sdk = '?' }
    Write-Host "phone:   $model (Android SDK $sdk)"
    $ui = Get-OneUi
    if ($ui) {
        Write-Host "One UI:  $ui"
        if ([int]$ui.Split('.')[0] -lt 8) {
            Write-Warn "One UI $ui is too old: DeX on a virtual display needs One UI 8+."
        } else {
            Write-Ok 'One UI 8+ detected.'
            if ($ui -eq '8.0') { Write-Host 'One UI 8.0: desktop windowing works out of the box.' }
            else { Write-Host 'One UI 8.5+/9: dex forces desktop windowing on the DeX display at start (the fix for fullscreen-only apps).' }
        }
    } else {
        Write-Warn 'Could not read One UI version (not a Samsung phone, or One UI < 8?).'
    }
    $wk = Get-Wakefulness
    if ($wk) { Write-Host "power:   $wk" }
    $ffs = Get-PhoneValue @('settings', 'get', 'global', 'enable_freeform_support')
    $wantedFf = Get-WantedFreeformSupport
    if (!$wantedFf) { $wantedFf = '<unchanged>' }
    Write-Host "freeform support: $ffs (dex sets it to $wantedFf while DeX runs)"
    Write-Host "display mode:     $(Get-WantedDisplay) (overlay = real desktop windows on One UI 8.5+/9; virtual = scrcpy display)"
    Write-Host "force desktop:    $(Get-PhoneValue @('settings', 'get', 'global', 'force_desktop_mode_on_external_displays')) (DEX_FORCE_DESKTOP=$(Get-Cfg 'DEX_FORCE_DESKTOP'))"
    Write-Host "mouse mode:       $(Get-WantedMouse) (uhid = real HID mouse on the DeX display, needs Android 15+; sdk = injected touch)"
    $remembered = Get-RememberedPhone
    if ($remembered) { Write-Host "remembered: $remembered" }
    return 0
}
function Invoke-Update {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $installer = ''
    if ($env:DEX_SOURCE_DIR) { $installer = Join-Path $env:DEX_SOURCE_DIR 'install.ps1' }
    $downloaded = $false
    if (!$installer -or !(Test-Path -LiteralPath $installer)) {
        $repo = if ($env:DEX_REPO) { $env:DEX_REPO } else { 'ErenKaynak/dex-script' }
        $installer = Join-Path ([IO.Path]::GetTempPath()) ("dex-install-" + [guid]::NewGuid().ToString() + '.ps1')
        $downloaded = $true
    }
    try {
        if ($downloaded) { Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/main/install.ps1" -OutFile $installer }
        $global:LASTEXITCODE = 0
        & $installer
        if ($LASTEXITCODE -ne 0) { throw 'The installer failed.' }
    } finally { if ($downloaded -and (Test-Path $installer)) { Remove-Item -LiteralPath $installer -Force } }
    return 0
}
function Invoke-Uninstall {
    $bin = Join-Path $script:root 'bin'
    foreach ($scope in @('User', 'Process')) {
        $pathValue = [Environment]::GetEnvironmentVariable('Path', $scope)
        $clean = @($pathValue -split ';' | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $clean, $scope)
    }
    foreach ($folder in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
        $link = Join-Path $folder 'Galaxy DeX.lnk'
        if (Test-Path $link) { Remove-Item -LiteralPath $link -Force }
    }
    $bundledAdb = Join-Path $script:root 'scrcpy/adb.exe'
    if (Test-Path $bundledAdb) { $ErrorActionPreference = 'Continue'; & $bundledAdb kill-server 2>&1 | Out-Null; $ErrorActionPreference = 'Stop' }
    # Remove only what dex created; DEX_HOME may point at a shared folder.
    $scrcpyDir = Join-Path $script:root 'scrcpy'
    if (Test-Path $scrcpyDir) { Remove-Item -LiteralPath $scrcpyDir -Recurse -Force }
    # bin holds the running dex.cmd; cmd re-reads it after we exit, so delete it a moment later.
    $cleanup = 'ping -n 3 127.0.0.1 >nul & rmdir /s /q "' + $bin + '" & rmdir "' + $script:root + '"'
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', $cleanup) -WindowStyle Hidden
    if (Test-Path $script:configDir) { Remove-Item -LiteralPath $script:configDir -Recurse -Force }
    Write-Ok 'dex removed.'
    exit 0
}
# --- interactive menu (TUI) -------------------------------------------------------
function Test-Interactive {
    if ($env:DEX_NO_TUI -eq '1') { return $false }
    if (![Environment]::UserInteractive) { return $false }
    try { return (!([Console]::IsInputRedirected) -and !([Console]::IsOutputRedirected)) } catch { return $false }
}
function Clear-Screen {
    $script:menuBottom = 0
    try { Clear-Host } catch { Write-Verbose 'Cannot clear the screen.' }
}
function Get-ConsoleSize {
    $size = @{ Width = 80 }
    try {
        if ([Console]::WindowWidth -gt 0) { $size.Width = [Console]::WindowWidth }
    } catch { Write-Verbose 'No console size.' }
    return $size
}
# Menu lines are written in colored pieces; Write-EndLine pads the rest of the line with spaces
# (instead of clearing the screen) so each redraw overwrites the previous frame without flicker.
function Write-Seg([string]$Text, [string]$Color = '', [switch]$Bold) {
    $display = $Text
    if ($Bold -and $script:vtBold) { $display = ([string][char]27) + '[1m' + $Text + ([string][char]27) + '[22m' }
    if ($Color) { Write-Host $display -NoNewline -ForegroundColor $Color } else { Write-Host $display -NoNewline }
    $script:col += $Text.Length
}
function Write-EndLine {
    $fill = $script:frameW - 1 - ($script:col % $script:frameW)
    if ($fill -gt 0) { Write-Host (' ' * $fill) -NoNewline }
    Write-Host ''
    $script:col = 0
}
function Format-Cell([string]$Text, [int]$Width) {
    if ($Width -lt 0) { $Width = 0 }
    return $Text.PadRight($Width)
}
function Write-BoxLine([string]$Left, [string]$Right) {
    Write-Seg ('  ' + $Left + ($script:bx.H * $script:boxW) + $Right) 'Cyan'
    Write-EndLine
}
function Write-BoxRow([string]$Text, [string]$Color = '') {
    Write-Seg ('  ' + $script:bx.V) 'Cyan'
    Write-Seg (' ' + (Format-Cell $Text ($script:boxW - 2)) + ' ') $Color
    Write-Seg $script:bx.V 'Cyan'
    Write-EndLine
}
function Write-BoxItem([string]$Key, [string]$Label, [string]$Desc, [string]$Mark = '') {
    Write-Seg ('  ' + $script:bx.V + '  ') 'Cyan'
    Write-Seg (Format-Cell $Key 2) 'Cyan' -Bold
    Write-Seg ' '
    Write-Seg (Format-Cell $Label 9) -Bold
    Write-Seg ' '
    Write-Seg (Format-Cell $Desc ($script:boxW - 15 - $Mark.Length))
    Write-Seg $Mark 'Green'
    Write-Seg $script:bx.V 'Cyan'
    Write-EndLine
}
function Write-BoxKv([string]$Label, [string]$Value, [string]$Color = '', [string]$Right = '') {
    Write-Seg ('  ' + $script:bx.V + ' ') 'Cyan'
    Write-Seg (Format-Cell $Label 9) 'DarkGray'
    Write-Seg (Format-Cell $Value ($script:boxW - 11 - $Right.Length)) $Color
    Write-Seg $Right 'DarkGray'
    Write-Seg (' ' + $script:bx.V) 'Cyan'
    Write-EndLine
}
# Returns @{ Text; Color; Batt } for the Phone row. Model and One UI are cached per serial,
# the battery level is re-read on every refresh.
function Get-TuiPhone {
    $info = @{ Text = 'no phone: plug in USB, or p = pair'; Color = 'Red'; Batt = '' }
    $remembered = Get-RememberedPhone
    if ($remembered) { $info.Text = "not connected: $remembered $($script:bx.Dot) c = connect" }
    Invoke-DeviceScan
    $s = ''; $via = ''
    if ($script:usbList.Count -gt 0) { $s = $script:usbList[0]; $via = 'USB' }
    elseif ($script:tcpList.Count -gt 0) { $s = $script:tcpList[0]; $via = 'Wi-Fi' }
    elseif ($script:unauth.Count -gt 0) {
        $info.Text = 'UNAUTHORIZED: accept the prompt on the phone'; $info.Color = 'Yellow'
        return $info
    }
    if (!$s) { return $info }
    $script:serial = $s
    if ($s -ne $script:tuiSeen) {
        $m = Get-PhoneValue @('getprop', 'ro.product.marketname')
        if (!$m) { $m = Get-PhoneValue @('getprop', 'ro.product.model') }
        $ui = Get-OneUi
        if ($ui) { $m = "$m $($script:bx.Dot) One UI $ui" }
        $script:tuiModel = $m
        $script:tuiSeen = $s
    }
    foreach ($l in @(Invoke-Phone @('dumpsys', 'battery'))) {
        if ($l -match '^\s*level:\s*(\d+)') { $info.Batt = "$($Matches[1])%"; break }
    }
    $name = if ($script:tuiModel) { $script:tuiModel } else { $s }
    $info.Text = "$name $($script:bx.Dot) $via"
    $info.Color = 'Green'
    return $info
}
# Draws one frame in place: cursor to the top of the window, every line padded to the console width,
# then whatever is left below the prompt is blanked.
function Show-Menu {
    if (!$script:scrcpyVer) {
        $script:scrcpyVer = if ((Get-ScrcpyLine) -match '^scrcpy\s+(\S+)') { $Matches[1] } else { '?' }
    }
    $dot = $script:bx.Dot
    $screen = Get-Cfg 'DEX_SCREEN'
    if (!$screen) { $screen = 'on' }
    $mode = if ((Get-Cfg 'DEX_FULLSCREEN') -eq '1') { 'fullscreen' } else { 'window' }
    $res = Get-Cfg 'DEX_RES'
    if (!$res) { $res = "$(Get-DefaultResolution 80) auto" }
    $dpi = Get-Cfg 'DEX_DPI'
    if (!$dpi) { $dpi = 'auto' }
    $last = Get-Cfg 'DEX_LAST_PROFILE'
    if ($last -notin @('code', 'school', 'movie', 'mirror')) { $last = 'code' }
    $mark = @{ code = ''; school = ''; movie = ''; mirror = '' }
    $mark[$last] = 'last '
    $phone = Get-TuiPhone
    $size = Get-ConsoleSize
    $script:frameW = $size.Width
    $script:col = 0
    try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Screen }
    Write-EndLine
    if ($size.Width -ge 64) {
        foreach ($b in ($script:banner -split '\r?\n')) { Write-Seg ('  ' + $b) 'Cyan'; Write-EndLine }
        Write-EndLine
    }
    Write-BoxLine $script:bx.TL $script:bx.TR
    $right = "scrcpy $($script:scrcpyVer)"
    Write-Seg ('  ' + $script:bx.V + ' ') 'Cyan'
    Write-Seg (Format-Cell 'Galaxy DeX on your PC' ($script:boxW - 2 - $right.Length)) -Bold
    Write-Seg $right 'DarkGray'
    Write-Seg (' ' + $script:bx.V) 'Cyan'
    Write-EndLine
    Write-BoxLine $script:bx.ML $script:bx.MR
    Write-BoxKv 'Phone' $phone.Text $phone.Color $phone.Batt
    $mouse = Get-Cfg 'DEX_MOUSE'
    if (!$mouse) { $mouse = 'auto' }
    $display = Get-Cfg 'DEX_DISPLAY'
    if (!$display) { $display = 'auto' }
    Write-BoxKv 'Settings' "phone $screen $dot $mode $dot $display $dot mouse $mouse $dot $res @ $dpi"
    Write-BoxLine $script:bx.ML $script:bx.MR
    Write-BoxItem '1' 'Code' 'crisp text: coding, T3, browser' $mark['code']
    Write-BoxItem '2' 'School' 'more room: Word / Excel side by side' $mark['school']
    Write-BoxItem '3' 'Movie' 'high bitrate, H.265, smooth audio' $mark['movie']
    Write-BoxItem '4' 'Mirror' 'plain phone screen, no DeX' $mark['mirror']
    Write-BoxRow ''
    Write-BoxItem 'p' 'Pair' 'Wi-Fi pairing with a code (no cable)'
    Write-BoxItem 'c' 'Connect' 'reconnect over Wi-Fi'
    Write-BoxItem 'w' 'Wi-Fi' 'USB plugged in -> switch to Wi-Fi'
    Write-BoxItem 'k' 'Keyboard' 'phone keyboard layout (Turkish Q)'
    Write-BoxItem 's' 'Screen' 'phone panel while DeX runs: on / dim / off'
    Write-BoxItem 'f' 'Window' 'toggle window / fullscreen start'
    Write-BoxItem 'r' 'Size' 'set window size and DPI'
    Write-BoxItem 'm' 'Mouse' 'real HID mouse (uhid) / injected touch (sdk)'
    Write-BoxItem 'o' 'Display' 'auto / overlay (One UI 9 windows) / virtual'
    Write-BoxItem 'l' 'Log' 'start Code with a phone log for bug reports'
    Write-BoxItem 'd' 'Doctor' 'versions, devices, One UI check'
    Write-BoxItem 'x' 'Wake' 'unfreeze a stuck DeX window'
    Write-BoxItem 'u' 'Update' 're-run the installer'
    Write-BoxItem 'q' 'Quit' ''
    Write-BoxLine $script:bx.BL $script:bx.BR
    if ($script:tuiMsg[0]) {
        Write-Seg ('  ' + $script:tuiMsg[0]) $script:tuiMsg[1]
    } else {
        $hint = "  Enter = $last $dot F11 fullscreen in DeX $dot Alt+q closes DeX $dot menu refreshes itself"
        Write-Seg $hint 'DarkGray'
    }
    Write-EndLine
    Write-Seg ('  Choose ' + $script:bx.Arrow + ' ')
    try {
        $left = [Console]::CursorLeft; $top = [Console]::CursorTop
        $rest = $script:frameW - 1 - $left
        if ($rest -gt 0) { Write-Host (' ' * $rest) -NoNewline }
        for ($r = $top + 1; $r -le $script:menuBottom; $r++) {
            [Console]::SetCursorPosition(0, $r)
            Write-Host (' ' * ($script:frameW - 1)) -NoNewline
        }
        [Console]::SetCursorPosition($left, $top)
        $script:menuBottom = $top
    } catch { Write-Verbose 'Cannot clear below the menu.' }
}
# Waits up to $Seconds for a key (polling every 200 ms); returns $null on timeout.
function Wait-MenuKey([int]$Seconds) {
    $deadline = [datetime]::UtcNow.AddSeconds($Seconds)
    while ([datetime]::UtcNow -lt $deadline) {
        if ([Console]::KeyAvailable) { return [Console]::ReadKey($true) }
        Start-Sleep -Milliseconds 200
    }
    return $null
}
# Runs a command, then waits for a key so its output can be read.
function Invoke-MenuAction([scriptblock]$Action) {
    Clear-Screen
    $rc = 0
    try { $rc = Get-ExitCode (& $Action) } catch { Write-Err $_.Exception.Message; $rc = 1 }
    if ($rc -eq 2) { $script:tuiMsg = @('No phone found. Plug in USB, or press p to pair over Wi-Fi.', 'Yellow') }
    elseif ($rc -ne 0) { $script:tuiMsg = @("Last command exited with code $rc.", 'Yellow') }
    Write-Host ''
    Write-Host '  Press any key to return to the menu...' -NoNewline -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
    Clear-Screen
}
function Invoke-Menu {
    Test-ToolInstallation
    $profileKey = @{ code = '1'; school = '2'; movie = '3'; mirror = '4' }
    Clear-Screen
    while ($true) {
        Show-Menu
        $key = Wait-MenuKey 5
        if ($null -eq $key) { continue } # timeout: redraw to refresh the phone status
        $script:tuiMsg = @('', 'DarkGray')
        $choice = ([string]$key.KeyChar).ToLowerInvariant()
        if ($key.Key -eq 'Enter') {
            $lastProfile = Get-Cfg 'DEX_LAST_PROFILE'
            if ($lastProfile -notin @('school', 'movie', 'mirror')) { $lastProfile = 'code' }
            $choice = $profileKey[$lastProfile]
        } elseif ($key.Key -eq 'Escape') { $choice = 'q' }
        switch ($choice) {
            '1' { Invoke-MenuAction { Invoke-DexStart 'code' } }
            '2' { Invoke-MenuAction { Invoke-DexStart 'school' } }
            '3' { Invoke-MenuAction { Invoke-DexStart 'movie' } }
            '4' { Invoke-MenuAction { Invoke-DexStart 'mirror' } }
            'l' {
                $previousDebug = $script:opt.Debug
                try { $script:opt.Debug = $true; Invoke-MenuAction { Invoke-DexStart 'code' } }
                finally { $script:opt.Debug = $previousDebug }
            }
            'o' {
                switch (Get-Cfg 'DEX_DISPLAY') {
                    'overlay' {
                        Save-ConfigValue 'DEX_DISPLAY' 'virtual'
                        $script:tuiMsg = @('Display: scrcpy virtual display (resizes with the window; no title bars on One UI 8.5+/9).', 'Yellow')
                    }
                    'virtual' {
                        Save-ConfigValue 'DEX_DISPLAY' ''
                        $script:tuiMsg = @('Display: auto (overlay on One UI 8.5+/9, virtual otherwise).', 'Green')
                    }
                    default {
                        Save-ConfigValue 'DEX_DISPLAY' 'overlay'
                        $script:tuiMsg = @('Display: overlay (real desktop windows; fixed size; preview on the phone screen).', 'Green')
                    }
                }
            }
            'm' {
                if ((Get-Cfg 'DEX_MOUSE') -eq 'sdk') {
                    Save-ConfigValue 'DEX_MOUSE' 'uhid'
                    $script:tuiMsg = @('Mouse: real HID mouse on the DeX display (title bars drag like native DeX; Alt releases the pointer).', 'Green')
                } else {
                    Save-ConfigValue 'DEX_MOUSE' 'sdk'
                    $script:tuiMsg = @('Mouse: injected touch-style clicks (pointer never captured; window title bars may not drag on One UI 8.5+).', 'Yellow')
                }
            }
            'p' { Invoke-MenuAction { Invoke-Pair } }
            'c' { Invoke-MenuAction { Invoke-ConnectCmd '' } }
            'w' { Invoke-MenuAction { Invoke-Wifi } }
            'k' { Invoke-MenuAction { Invoke-Keyboard } }
            'd' { Invoke-MenuAction { Invoke-Doctor } }
            'x' { Invoke-MenuAction { Invoke-Wake } }
            'h' { Invoke-MenuAction { Show-Help } }
            '?' { Invoke-MenuAction { Show-Help } }
            'u' { Write-Host ''; return (Get-ExitCode (Invoke-Update)) }
            'q' { Write-Host ''; return 0 }
            's' {
                $current = Get-Cfg 'DEX_SCREEN'
                if ($current -eq 'dim') {
                    Save-ConfigValue 'DEX_SCREEN' 'off'
                    $script:tuiMsg = @('Phone screen OFF while DeX runs. If DeX freezes, press x (wake) and switch back to on/dim.', 'Yellow')
                } elseif ($current -eq 'off') {
                    Save-ConfigValue 'DEX_SCREEN' 'on'
                    $script:tuiMsg = @('Phone screen stays ON while DeX runs (safest).', 'Green')
                } else {
                    Save-ConfigValue 'DEX_SCREEN' 'dim'
                    $script:tuiMsg = @('Phone screen DIMMED while DeX runs (brightness restored on exit).', 'Green')
                }
            }
            'f' {
                if ((Get-Cfg 'DEX_FULLSCREEN') -eq '1') {
                    Save-ConfigValue 'DEX_FULLSCREEN' '0'
                    $script:tuiMsg = @('DeX starts in a resizable window (F11 toggles fullscreen).', 'Green')
                } else {
                    Save-ConfigValue 'DEX_FULLSCREEN' '1'
                    $script:tuiMsg = @("DeX starts fullscreen at your monitor's resolution, like a real DeX monitor.", 'Green')
                }
            }
            'r' {
                Write-Host ''
                $newRes = Read-Host '  Window size WxH (empty = auto, 80% of screen)'
                $newDpi = Read-Host '  DPI (empty = profile default; 160 normal, 140 denser, 200 bigger)'
                Clear-Screen
                if ($newRes -notmatch '^(\d+x\d+)?$') { $script:tuiMsg = @('Size must look like 1600x900.', 'Red') }
                elseif ($newDpi -notmatch '^\d*$') { $script:tuiMsg = @('DPI must be a number.', 'Red') }
                else {
                    Save-ConfigValue 'DEX_RES' $newRes
                    Save-ConfigValue 'DEX_DPI' $newDpi
                    $script:tuiMsg = @('Saved.', 'Green')
                }
            }
            default { $script:tuiMsg = @("Unknown key '$choice'. Press 1-4 to start DeX, q to quit.", 'DarkGray') }
        }
    }
}
# --- main -------------------------------------------------------------------------
try {
    $command = ''
    $position = 0
    if ($args.Count -gt 0 -and !([string]$args[0]).StartsWith('-')) { $command = [string]$args[0]; $position = 1 }
    $positional = @()
    while ($position -lt $args.Count) {
        $arg = [string]$args[$position]; $position++
        if ($arg -like '--display=*') { $script:opt.Display = $arg.Substring(10); continue }
        if ($arg -like '--mouse=*') { $script:opt.Mouse = $arg.Substring(8); continue }
        if ($arg -like '--res=*') { $script:opt.Res = $arg.Substring(6); continue }
        if ($arg -like '--dpi=*') { $script:opt.Dpi = $arg.Substring(6); continue }
        if ($arg -like '--screen=*') { $script:opt.Screen = $arg.Substring(9); continue }
        switch ($arg) {
            '--' { $script:opt.Raw = @($args | Select-Object -Skip $position); $position = $args.Count }
            '--res' { if ($position -ge $args.Count) { throw '--res needs WxH.' }; $script:opt.Res = [string]$args[$position]; $position++ }
            '--dpi' { if ($position -ge $args.Count) { throw '--dpi needs a number.' }; $script:opt.Dpi = [string]$args[$position]; $position++ }
            '--screen' { if ($position -ge $args.Count) { throw '--screen needs on, dim or off.' }; $script:opt.Screen = [string]$args[$position]; $position++ }
            '--mouse' { if ($position -ge $args.Count) { throw '--mouse needs uhid or sdk' }; $script:opt.Mouse = [string]$args[$position]; $position++ }
            '--display' { if ($position -ge $args.Count) { throw '--display needs auto, overlay or virtual' }; $script:opt.Display = [string]$args[$position]; $position++ }
            '--debug' { $script:opt.Debug = $true }
            '--usb' { $script:opt.Mode = 'usb' }
            '--wifi' { $script:opt.Mode = 'wifi' }
            '--screen-off' { $script:opt.Screen = 'off' }
            '--fullscreen' { $script:opt.Fullscreen = '1' }
            '--no-freeform' { $script:opt.Freeform = '0' }
            { $_ -in @('--menu', '--tui') } { $command = 'menu' }
            { $_ -in @('-h', '--help') } { $command = 'help' }
            default {
                if ($arg.StartsWith('-')) { throw "Unknown option: $arg (see: dex help)" }
                $positional += $arg
            }
        }
    }
    if ($script:opt.Res -and $script:opt.Res -notmatch '^[1-9]\d*x[1-9]\d*$') { throw '--res must look like 1600x900.' }
    if ($script:opt.Dpi -and $script:opt.Dpi -notmatch '^[1-9]\d*$') { throw '--dpi must be a positive number.' }
    if ($script:opt.Screen -notin @('', 'on', 'dim', 'off')) { throw '--screen must be on, dim or off.' }
    if ($script:opt.Mouse -notin @('', 'uhid', 'sdk')) { throw '--mouse must be uhid or sdk' }
    if ($script:opt.Display -notin @('', 'auto', 'overlay', 'virtual')) { throw '--display must be auto, overlay or virtual' }
    if ($script:opt.Display -eq 'auto') { $script:opt.Display = '' }
    if (!$command) { $command = if (Test-Interactive) { 'menu' } else { 'code' } }
    $rc = 0
    switch ($command) {
        'menu' { $rc = Invoke-Menu }
        { $_ -in @('code', 'school', 'movie', 'mirror') } { $rc = Invoke-DexStart $command }
        'debug' { $script:opt.Debug = $true; $rc = Invoke-DexStart 'code' }
        'pair' { $rc = Invoke-Pair }
        'connect' { $rc = Invoke-ConnectCmd $(if ($positional.Count -gt 0) { $positional[0] } else { '' }) }
        'wifi' { $rc = Invoke-Wifi }
        'wake' { $rc = Invoke-Wake }
        'keyboard' { $rc = Invoke-Keyboard }
        'doctor' { $rc = Invoke-Doctor }
        'update' { $rc = Invoke-Update }
        'uninstall' { $rc = Invoke-Uninstall }
        'help' { Show-Help }
        default { throw "Unknown command: $command. Run: dex help" }
    }
    exit (Get-ExitCode $rc)
} catch { Write-Host "DeX: $($_.Exception.Message)"; exit 1 }
