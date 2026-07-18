param(
    [Parameter(Mandatory = $true)]
    [string]$InstalledExe,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,
    [switch]$AuditOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Test-PathWithin([string]$Path, [string]$Root) {
    $fullPath = Get-FullPath $Path
    $fullRoot = (Get-FullPath $Root) + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ShortcutRecord([string]$Path, $Shell) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $shortcut = $Shell.CreateShortcut($Path)
        return [ordered]@{
            path = Get-FullPath $Path
            target = [string]$shortcut.TargetPath
            arguments = [string]$shortcut.Arguments
        }
    } catch {
        return [ordered]@{
            path = Get-FullPath $Path
            target = ""
            arguments = ""
            error = $_.Exception.Message
        }
    }
}

$appName = "UniLink Control"
$programFilesRoot = Get-FullPath (Join-Path $env:ProgramFiles $appName)
$installedExe = Get-FullPath $InstalledExe
if (-not (Test-PathWithin $installedExe $programFilesRoot)) {
    throw "Installed executable is outside the expected Program Files root: $installedExe"
}
if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
    throw "Installed executable does not exist: $installedExe"
}

$installedItem = Get-Item -LiteralPath $installedExe
$actualVersion = [string]$installedItem.VersionInfo.ProductVersion
if (-not $actualVersion.StartsWith($ExpectedVersion, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Installed version mismatch: expected $ExpectedVersion, got $actualVersion"
}

$legacyRoot = Get-FullPath (Join-Path $env:LOCALAPPDATA "Programs\$appName")
$legacyExe = Get-FullPath (Join-Path $legacyRoot "$appName.exe")
$backupBase = Get-FullPath (Join-Path $env:LOCALAPPDATA "$appName\MigrationBackups")
if (-not (Test-PathWithin (Join-Path $backupBase "probe") (Join-Path $env:LOCALAPPDATA $appName))) {
    throw "Migration backup root is outside the expected LocalAppData directory."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $backupBase "$stamp-$PID"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$configSource = Get-FullPath (Join-Path $env:APPDATA "$appName\config")
if (Test-Path -LiteralPath $configSource -PathType Container) {
    Copy-Item -LiteralPath $configSource -Destination (Join-Path $backupDir "config") -Recurse -Force
}

$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "$appName.lnk"),
    (Join-Path $env:PUBLIC "Desktop\$appName.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$appName\$appName.lnk"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$appName\$appName.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\$appName Tray.lnk"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Startup\$appName Tray.lnk")
)
$shortcutRecords = @($shortcutPaths | ForEach-Object { Get-ShortcutRecord $_ $shell } | Where-Object { $null -ne $_ })
$staleShortcuts = @($shortcutRecords | Where-Object {
    $_.target -and (Test-PathWithin $_.target $legacyRoot)
})

$runRecords = @()
foreach ($registryPath in @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
)) {
    if (-not (Test-Path -LiteralPath $registryPath)) {
        continue
    }
    $item = Get-ItemProperty -LiteralPath $registryPath
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -like "PS*") {
            continue
        }
        $value = [string]$property.Value
        if ($value -and $value.IndexOf($legacyRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $runRecords += [ordered]@{
                registry = $registryPath
                name = $property.Name
                value = $value
            }
        }
    }
}

$protocolRecords = @()
foreach ($registryPath in @(
    "HKCU:\Software\Classes\$appName",
    "HKCU:\Software\Classes\.$appName"
)) {
    if (Test-Path -LiteralPath $registryPath) {
        $protocolRecords += [ordered]@{
            registry = $registryPath
            values = (Get-ItemProperty -LiteralPath $registryPath | Select-Object * -ExcludeProperty PS*)
        }
    }
}

$legacyInfo = [ordered]@{
    path = $legacyExe
    exists = (Test-Path -LiteralPath $legacyExe -PathType Leaf)
    version = ""
    sha256 = ""
}
if ($legacyInfo.exists) {
    $legacyItem = Get-Item -LiteralPath $legacyExe
    $legacyInfo.version = [string]$legacyItem.VersionInfo.ProductVersion
    $legacyInfo.sha256 = (Get-FileHash -LiteralPath $legacyExe -Algorithm SHA256).Hash.ToLowerInvariant()
}

$service = Get-CimInstance Win32_Service -Filter "Name='$appName'" -ErrorAction SilentlyContinue
$inventory = [ordered]@{
    created_at = (Get-Date).ToString("o")
    expected_version = $ExpectedVersion
    installed = [ordered]@{
        path = $installedExe
        version = $actualVersion
        sha256 = (Get-FileHash -LiteralPath $installedExe -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    legacy = $legacyInfo
    service_path = if ($null -eq $service) { "" } else { [string]$service.PathName }
    config_source = $configSource
    shortcuts = $shortcutRecords
    stale_run_entries = $runRecords
    user_protocol_keys = $protocolRecords
}
$inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupDir "inventory.json") -Encoding UTF8

if ($AuditOnly) {
    [ordered]@{
        completed_at = (Get-Date).ToString("o")
        backup = $backupDir
        installed_exe = $installedExe
        installed_version = $actualVersion
        audit_only = $true
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDir "completed.json") -Encoding UTF8
    Write-Output "UniLink migration audit backup: $backupDir"
    return
}

$shortcutBackup = Join-Path $backupDir "shortcuts"
if ($staleShortcuts.Count -gt 0) {
    New-Item -ItemType Directory -Path $shortcutBackup -Force | Out-Null
}
foreach ($record in $staleShortcuts) {
    $shortcutPath = [string]$record.path
    $backupName = ([IO.Path]::GetFileNameWithoutExtension($shortcutPath) + "-" + [Guid]::NewGuid().ToString("N") + ".lnk")
    Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $shortcutBackup $backupName) -Force
    Remove-Item -LiteralPath $shortcutPath -Force
}

foreach ($record in $runRecords) {
    Remove-ItemProperty -LiteralPath $record.registry -Name $record.name -Force
}
foreach ($record in $protocolRecords) {
    $registryPath = [string]$record.registry
    $commandPath = Join-Path $registryPath "shell\open\command"
    $command = if (Test-Path -LiteralPath $commandPath) { [string](Get-Item -LiteralPath $commandPath).GetValue("") } else { "" }
    if ($command.IndexOf($legacyRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force
    }
}

if ($legacyInfo.exists) {
    Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -and (Test-PathWithin $_.ExecutablePath $legacyRoot)
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $disabledExe = "$legacyExe.disabled-$stamp"
    Rename-Item -LiteralPath $legacyExe -NewName ([IO.Path]::GetFileName($disabledExe))
}

[ordered]@{
    completed_at = (Get-Date).ToString("o")
    backup = $backupDir
    installed_exe = $installedExe
    installed_version = $actualVersion
    legacy_executable_disabled = [bool]$legacyInfo.exists
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDir "completed.json") -Encoding UTF8

Write-Output "UniLink migration backup: $backupDir"
