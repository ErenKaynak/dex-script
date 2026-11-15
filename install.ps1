# Galaxy DeX per-user installer. Compatible with Windows PowerShell 5.1.
#   irm https://raw.githubusercontent.com/ErenKaynak/dex-script/main/install.ps1 | iex
# Runs inside a script block so preferences don't leak into the caller's session (iex),
# and reports failure with throw instead of exit (exit would close the user's window).
& {
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try {
    $repo = if ($env:DEX_REPO) { $env:DEX_REPO } else { 'ErenKaynak/dex-script' }
    $version = if ($env:DEX_SCRCPY_VERSION) { $env:DEX_SCRCPY_VERSION } else { '5.0.1' }
    $root = if ($env:DEX_HOME) { $env:DEX_HOME } else { Join-Path $env:LOCALAPPDATA 'dex' }
    $bin = Join-Path $root 'bin'
    $scrcpy = Join-Path $root 'scrcpy'
    $raw = "https://raw.githubusercontent.com/$repo/main"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $versionFile = Join-Path $scrcpy 'VERSION'
    if (!(Test-Path $versionFile) -or (Get-Content $versionFile -Raw).Trim() -ne $version) {
        $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        switch ($arch) {
            'ARM64' { $platform = 'winarm64' }
            'AMD64' { $platform = 'win64' }
            default { throw "Unsupported Windows architecture: $arch. Use x64 or ARM64 Windows." }
        }
        $asset = "scrcpy-$platform-v$version.zip"
        $release = "https://github.com/Genymobile/scrcpy/releases/download/v$version"
        $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            $zip = Join-Path $temp $asset
            Invoke-WebRequest -UseBasicParsing "$release/$asset" -OutFile $zip
            # Saved to a file: GitHub serves it as octet-stream, so .Content would be a byte[].
            $sumsFile = Join-Path $temp 'SHA256SUMS.txt'
            Invoke-WebRequest -UseBasicParsing "$release/SHA256SUMS.txt" -OutFile $sumsFile
            $sums = Get-Content -LiteralPath $sumsFile -Raw
            $expected = $null
            foreach ($line in ($sums -split "`n")) {
                if ($line.Trim() -match '^([a-fA-F0-9]{64})\s+\*?(.+)$' -and $Matches[2] -eq $asset) { $expected = $Matches[1] }
            }
            if (!$expected -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected) { throw 'SHA256 verification failed. Installation stopped.' }
            $expanded = Join-Path $temp 'expanded'
            Expand-Archive -LiteralPath $zip -DestinationPath $expanded
            $payload = Join-Path $expanded "scrcpy-$platform-v$version"
            if (!(Test-Path (Join-Path $payload 'scrcpy.exe'))) { throw 'The archive does not contain scrcpy.exe.' }
            # A running adb server locks adb.exe; stop it before replacing the folder.
            $oldAdb = Join-Path $scrcpy 'adb.exe'
            if (Test-Path $oldAdb) { $ErrorActionPreference = 'Continue'; & $oldAdb kill-server 2>&1 | Out-Null; $ErrorActionPreference = 'Stop' }
            if (Test-Path $scrcpy) { Remove-Item -LiteralPath $scrcpy -Recurse -Force }
            Move-Item -LiteralPath $payload -Destination $scrcpy
            Set-Content -LiteralPath $versionFile -Value $version -Encoding ASCII
        } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
    foreach ($name in @('dex.ps1', 'dex.cmd')) {
        $target = Join-Path $bin $name
        if ($env:DEX_SOURCE_DIR) {
            $source = Join-Path $env:DEX_SOURCE_DIR "bin/$name"
            if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
        } else { Invoke-WebRequest -UseBasicParsing "$raw/bin/$name" -OutFile $target }
    }
    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -eq 0) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $bin).TrimStart(';')), 'User')
    }
    if (@($env:PATH -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -eq 0) { $env:PATH += ";$bin" }
    if ($env:DEX_NO_SHORTCUT -ne '1') {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($folder in @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
            $shortcut = $shell.CreateShortcut((Join-Path $folder 'Galaxy DeX.lnk'))
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $bin 'dex.ps1') + '" gui'
            $shortcut.WorkingDirectory = $root
            $shortcut.IconLocation = (Join-Path $scrcpy 'scrcpy.exe') + ',0'
            $shortcut.Save()
            $shortcut = $shell.CreateShortcut((Join-Path $folder 'Galaxy DeX (terminal).lnk'))
            # Keep the console open when dex fails (e.g. no phone found) so the message can be read.
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
            $shortcut.Arguments = '/c ""' + (Join-Path $bin 'dex.cmd') + '" || pause"'
            $shortcut.WorkingDirectory = $root
            $shortcut.IconLocation = (Join-Path $scrcpy 'scrcpy.exe') + ',0'
            $shortcut.Save()
        }
    }
    Write-Host "Galaxy DeX installed (scrcpy $version). Start with: dex"
    Write-Host '1. Settings > About phone > Software information > tap Build number 7 times.'
    Write-Host '2. Developer options > USB debugging ON (cable) and/or Wireless debugging ON (Wi-Fi).'
    Write-Host '3. Plug USB and accept "Allow USB debugging", or run: dex pair'
    Write-Host '4. Run: dex keyboard > choose Turkish Q (once).'
    Write-Host '5. Run: dex. Resize freely; F11 = fullscreen.'
} catch { throw "Galaxy DeX install failed: $($_.Exception.Message)" }
}
