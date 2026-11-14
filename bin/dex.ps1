# GNU-style arguments are intentionally parsed from $args.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = if ($env:DEX_HOME) { $env:DEX_HOME } else { Join-Path $env:LOCALAPPDATA 'dex' }
$configFile = Join-Path $env:APPDATA 'dex/config'
$config = @{}
if (Test-Path $configFile) {
    foreach ($line in Get-Content $configFile) {
        if ($line -match '^\s*([A-Z_]+)=(.*)$') { $config[$Matches[1]] = $Matches[2].Trim() }
    }
}
function Save-ConfigValue([string]$Key, [string]$Value) {
    $config[$Key] = $Value
    $lines = @()
    $found = $false
    if (Test-Path $configFile) {
        foreach ($line in Get-Content $configFile) {
            if ($line -match ('^\s*' + [regex]::Escape($Key) + '=')) {
                if (!$found) { $lines += "$Key=$Value"; $found = $true }
            } else { $lines += $line }
        }
    }
    if (!$found) { $lines += "$Key=$Value" }
    New-Item -ItemType Directory -Force -Path (Split-Path $configFile) | Out-Null
    $tempConfig = "$configFile.$([guid]::NewGuid().ToString()).tmp"
    try { Set-Content -LiteralPath $tempConfig -Value $lines -Encoding UTF8; Move-Item -LiteralPath $tempConfig -Destination $configFile -Force }
    finally { if (Test-Path $tempConfig) { Remove-Item -LiteralPath $tempConfig -Force } }
}
function Show-Help {
    Write-Host @'
Usage: dex [code|school|movie|mirror|pair|connect [ip:port]|wifi|keyboard|doctor|update|uninstall|help] [options]
Default: code. Options: --res WxH --dpi N --usb --wifi --screen-off --fullscreen -- [scrcpy args]
Resize the DeX window freely. F11 / Alt+f: fullscreen. dex keyboard: choose Turkish Q.
'@
}
function Invoke-Adb([string[]]$Arguments) {
    # Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $result = @(& $script:adb @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $($result -join ' ')" }
    return $result
}
function Get-DexDevice {
    foreach ($line in @(Invoke-Adb @('devices'))) {
        if ($line -match '^(\S+)\s+(device|unauthorized|offline)\b') {
            if ($Matches[2] -eq 'device') { $Matches[1] }
            elseif ($Matches[2] -eq 'unauthorized') { Write-Host 'Accept the "Allow USB debugging" prompt on your phone.' }
        }
    }
}
function Find-Endpoint {
    try {
        foreach ($line in @(Invoke-Adb @('mdns', 'services'))) {
            if ($line -match '_adb-tls-connect\._tcp\.?\s+(\S+:\d+)') { return $Matches[1] }
        }
    } catch { Write-Verbose $_ }
    return $null
}
function Connect-Endpoint([string]$Endpoint) {
    if ($Endpoint -notmatch '^[^\s]+:\d+$') { throw 'Enter an endpoint in IP:port format.' }
    $output = @(Invoke-Adb @('connect', $Endpoint))
    if (($output -join ' ') -notmatch '(already )?connected to') { throw ($output -join ' ') }
    Save-ConfigValue 'DEX_LAST_ENDPOINT' $Endpoint
    Write-Host ($output -join "`n")
}
function Show-WifiHint {
    Write-Host 'Use the same Wi-Fi network. School Wi-Fi may isolate clients: use Windows Settings > Mobile hotspot (phone joins PC), or a USB cable.'
    Write-Host 'A phone hotspot does not work: Wireless debugging requires the phone to be a Wi-Fi client.'
}
try {
    $command = 'code'
    $position = 0
    if ($args.Count -gt 0 -and !$args[0].StartsWith('-')) { $command = $args[0]; $position = 1 }
    if ($args.Count -gt 0 -and $args[0] -in @('-h', '--help')) { $command = 'help'; $position = 1 }
    $valid = @('code','school','movie','mirror','pair','connect','wifi','keyboard','doctor','update','uninstall','help')
    if ($command -notin $valid) { throw "Unknown command: $command. Run: dex help" }
    $res = $config['DEX_RES']; $dpi = $config['DEX_DPI']
    $usb = $false; $wifi = $false; $screenOff = $false; $fullscreen = $false
    $extra = @(); $endpoint = $null
    $starts = @('code','school','movie','mirror')
    while ($position -lt $args.Count) {
        $arg = $args[$position]; $position++
        if ($command -eq 'connect' -and !$arg.StartsWith('-') -and !$endpoint) { $endpoint = $arg; continue }
        if ($command -notin $starts) { throw "Unexpected argument: $arg" }
        switch ($arg) {
            '--' { $extra = @($args | Select-Object -Skip $position); $position = $args.Count }
            '--res' { if ($position -ge $args.Count) { throw '--res requires WxH.' }; $res = $args[$position]; $position++ }
            '--dpi' { if ($position -ge $args.Count) { throw '--dpi requires a positive number.' }; $dpi = $args[$position]; $position++ }
            '--usb' { $usb = $true }
            '--wifi' { $wifi = $true }
            '--screen-off' { $screenOff = $true }
            '--fullscreen' { $fullscreen = $true }
            default { throw "Unknown option: $arg. Run: dex help" }
        }
    }
    if ($usb -and $wifi) { throw 'Choose either --usb or --wifi.' }
    if ($res -and $res -notmatch '^[1-9]\d*x[1-9]\d*$') { throw '--res requires WxH, for example 1600x900.' }
    if ($dpi -and $dpi -notmatch '^[1-9]\d*$') { throw '--dpi requires a positive integer.' }
    if ($command -eq 'help') { Show-Help; exit 0 }
    if ($command -eq 'update') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $repo = if ($env:DEX_REPO) { $env:DEX_REPO } else { 'ErenKaynak/dex-script' }
        $installer = Join-Path ([IO.Path]::GetTempPath()) ("dex-install-" + [guid]::NewGuid().ToString() + '.ps1')
        try {
            Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/main/install.ps1" -OutFile $installer
            $global:LASTEXITCODE = 0
            & $installer
            if ($LASTEXITCODE -ne 0) { throw 'The installer failed.' }
        } finally { if (Test-Path $installer) { Remove-Item -LiteralPath $installer -Force } }
        exit 0
    }
    if ($command -eq 'uninstall') {
        $bin = Join-Path $root 'bin'
        foreach ($scope in @('User', 'Process')) {
            $pathValue = [Environment]::GetEnvironmentVariable('Path', $scope)
            $clean = @($pathValue -split ';' | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') }) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $clean, $scope)
        }
        foreach ($folder in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
            $link = Join-Path $folder 'Galaxy DeX.lnk'
            if (Test-Path $link) { Remove-Item -LiteralPath $link -Force }
        }
        $bundledAdb = Join-Path $root 'scrcpy/adb.exe'
        if (Test-Path $bundledAdb) { $ErrorActionPreference = 'Continue'; & $bundledAdb kill-server 2>&1 | Out-Null; $ErrorActionPreference = 'Stop' }
        # Remove only what dex created; DEX_HOME may point at a shared folder.
        $scrcpyDir = Join-Path $root 'scrcpy'
        if (Test-Path $scrcpyDir) { Remove-Item -LiteralPath $scrcpyDir -Recurse -Force }
        # bin holds the running dex.cmd; cmd re-reads it after we exit, so delete it a moment later.
        $cleanup = 'ping -n 3 127.0.0.1 >nul & rmdir /s /q "' + $bin + '" & rmdir "' + $root + '"'
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', $cleanup) -WindowStyle Hidden
        if (Test-Path (Split-Path $configFile)) { Remove-Item -LiteralPath (Split-Path $configFile) -Recurse -Force }
        Write-Host 'Galaxy DeX uninstalled.'; exit 0
    }
    $adb = Join-Path $root 'scrcpy/adb.exe'
    $scrcpy = Join-Path $root 'scrcpy/scrcpy.exe'
    $env:ADB = $adb
    if (!(Test-Path $adb) -or !(Test-Path $scrcpy)) { throw 'Bundled adb/scrcpy is missing. Re-run the installer.' }
    switch ($command) {
        'pair' {
            Write-Host 'Phone > Settings > Developer options > Wireless debugging ON > Pair device with pairing code.'
            try {
                $pairEndpoint = Read-Host 'IP:port in pairing dialog'
                $code = Read-Host '6-digit pairing code'
                if ($pairEndpoint -notmatch '^[^\s]+:\d+$' -or $code -notmatch '^\d{6}$') { throw 'Enter IP:port and a 6-digit pairing code.' }
                Invoke-Adb @('pair', $pairEndpoint, $code) | ForEach-Object { Write-Host $_ }
                $endpoint = Find-Endpoint
                if (!$endpoint) { $endpoint = Read-Host 'Connect IP address & Port on Wireless debugging main screen (different from pairing port)' }
                Connect-Endpoint $endpoint
            } catch { Show-WifiHint; throw }
            exit 0
        }
        'connect' {
            try {
                if (!$endpoint) { $endpoint = Find-Endpoint }
                if (!$endpoint) { $endpoint = $config['DEX_LAST_ENDPOINT'] }
                if (!$endpoint) { $endpoint = Read-Host 'Wireless debugging IP address & Port' }
                Connect-Endpoint $endpoint
            } catch { Show-WifiHint; throw }
            exit 0
        }
        'doctor' {
            & $scrcpy --version
            Invoke-Adb @('version') | ForEach-Object { Write-Host $_ }
            Invoke-Adb @('devices','-l') | ForEach-Object { Write-Host $_ }
        }
    }
    $devices = @(Get-DexDevice)
    $usbDevices = @($devices | Where-Object { $_ -notmatch ':' -and $_ -notmatch '_adb-tls-' })
    $tcpDevices = @($devices | Where-Object { $_ -notin $usbDevices })
    $serial = $null
    if ($command -eq 'wifi') { $usb = $true }
    if (!$wifi -and $usbDevices.Count -gt 0) { $serial = $usbDevices[0] }
    elseif (!$usb) {
        if ($tcpDevices.Count -gt 0) { $serial = $tcpDevices[0] }
        else {
            $candidates = @((Find-Endpoint), $config['DEX_LAST_ENDPOINT']) | Where-Object { $_ }
            foreach ($candidate in $candidates) {
                try {
                    Connect-Endpoint $candidate
                    $connected = @(Get-DexDevice | Where-Object { $_ -eq $candidate -or $_ -match ':' -or $_ -match '_adb-tls-' })
                    if ($connected.Count -gt 0) { $serial = $connected[0]; break }
                } catch { Write-Host $_.Exception.Message }
            }
        }
    }
    if (!$serial) {
        Write-Host 'No device. Plug in a USB cable, run dex pair, or plug USB and run dex wifi.'
        Write-Host 'USB not detected on Windows? Install the Samsung USB driver (needs admin) or use Wi-Fi: dex pair'
        exit 2
    }
    if ($devices.Count -gt 1) { Write-Host "Using device: $serial" }
    if ($command -eq 'wifi') {
        $address = (Invoke-Adb @('-s',$serial,'shell','ip','-f','inet','addr','show','wlan0')) -join ' '
        if ($address -notmatch '\binet\s+(\d+\.\d+\.\d+\.\d+)/') { throw 'Cannot find phone Wi-Fi IP. Connect the phone to Wi-Fi first.' }
        $endpoint = $Matches[1] + ':5555'
        Invoke-Adb @('-s',$serial,'tcpip','5555') | ForEach-Object { Write-Host $_ }
        Connect-Endpoint $endpoint
        Write-Host 'Unplug USB now. This connection lasts until the phone reboots.'; exit 0
    }
    if ($command -eq 'keyboard') {
        Invoke-Adb @('-s',$serial,'shell','am','start','-a','android.settings.HARD_KEYBOARD_SETTINGS') | ForEach-Object { Write-Host $_ }
        Write-Host 'Choose Turkish Q for the physical keyboard.'; exit 0
    }
    if ($command -eq 'doctor') {
        foreach ($property in @('ro.product.model','ro.build.version.sdk','ro.build.version.oneui')) {
            $value = (Invoke-Adb @('-s',$serial,'shell','getprop',$property)) -join ''
            Write-Host "${property}: $value"
            if ($property -eq 'ro.build.version.oneui' -and $value -match '^\d+$') {
                $oneUi = [int]$value
                Write-Host ('One UI: {0}.{1}' -f [math]::Floor($oneUi / 10000), ([math]::Floor($oneUi / 100) % 100))
                if ($oneUi -lt 80000) { Write-Host 'Warning: DeX on a virtual display requires One UI 8+.' }
            }
        }
        exit 0
    }
    if (!$config['DEX_KEYBOARD_HINT_SHOWN']) {
        Write-Host 'Keyboard tip: run dex keyboard and choose Turkish Q once.'
        Save-ConfigValue 'DEX_KEYBOARD_HINT_SHOWN' '1'
    }
    if (!$res) {
        $res = '1600x900'
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $res = '{0}x{1}' -f ([math]::Floor($area.Width * 0.8 / 8) * 8), ([math]::Floor($area.Height * 0.8 / 8) * 8)
        } catch { Write-Verbose 'Screen detection unavailable; using 1600x900.' }
    }
    if (!$dpi) { $dpi = if ($command -eq 'school') { '140' } else { '160' } }
    $scrcpyArgs = @('-s', $serial)
    if ($command -eq 'mirror') { $scrcpyArgs += @('--video-bit-rate=12M','--max-fps=60','--keyboard=uhid') }
    else {
        $mod = if ($config['DEX_SHORTCUT_MOD']) { $config['DEX_SHORTCUT_MOD'] } else { 'lalt' }
        $rate = switch ($command) { 'school' { 12 }; 'movie' { 24 }; default { 16 } }
        if ($serial -notin $usbDevices) { $rate = $rate / 2 }
        $scrcpyArgs += @("--new-display=$res/$dpi",'--flex-display','--no-vd-destroy-content','--keyboard=uhid','--mouse=sdk','--mouse-bind=++++:bhsn',"--window-title=Galaxy DeX ($command)","--shortcut-mod=$mod",'--video-codec=h264','--disable-screensaver','--max-fps=60',"--video-bit-rate=${rate}M")
        if ($serial -in $usbDevices) { $scrcpyArgs += '--stay-awake' }
        if ($command -eq 'movie') {
            $scrcpyArgs = @($scrcpyArgs | Where-Object { $_ -ne '--video-codec=h264' })
            $scrcpyArgs += @('--video-codec=h265','--audio-buffer=80')
            Write-Host 'Netflix / Disney+ / Prime use DRM: video stays black inside a PC window (Android blocks capture of protected content). For DRM content use a USB-C to HDMI cable/hub to a monitor/TV (real DeX), Wireless DeX to a smart TV, or the streaming site in the PC''s browser. YouTube, local files, Plex/Jellyfin work fine here.'
        }
    }
    if ($screenOff) { $scrcpyArgs += '--turn-screen-off' }
    if ($fullscreen) { $scrcpyArgs += '--fullscreen' }
    if ($config['DEX_EXTRA_ARGS']) {
        # Tokenize quoted arguments without evaluating config as PowerShell code.
        foreach ($match in [regex]::Matches($config['DEX_EXTRA_ARGS'], '(?:[^\s"'']+|"[^"]*"|''[^'']*'')+')) {
            $scrcpyArgs += ($match.Value -replace '"([^"]*)"|''([^'']*)''', '$1$2')
        }
    }
    $scrcpyArgs += $extra
    & $scrcpy @scrcpyArgs
    if ($LASTEXITCODE -ne 0) { exit 1 }
    exit 0
} catch { Write-Host "DeX: $($_.Exception.Message)"; exit 1 }
