param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$ReleaseUrl = "https://github.com/timoduizhang250/unilink-control-releases/releases/tag/$Version",

    [string]$WindowsX64Url = "",
    [string]$WindowsArm64Url = "",
    [string]$MacX64Url = "",
    [string]$MacArm64Url = "",
    [string]$AndroidX64Url = "",
    [string]$AndroidArm64Url = "",

    [string]$WindowsX64Sha256 = "",
    [string]$WindowsArm64Sha256 = "",
    [string]$MacX64Sha256 = "",
    [string]$MacArm64Sha256 = "",
    [string]$AndroidX64Sha256 = "",
    [string]$AndroidArm64Sha256 = "",

    [string]$Output = "latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Asset($Url, $Sha256) {
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }
    [ordered]@{
        url    = $Url
        sha256 = $Sha256
    }
}

$windows = [ordered]@{}
$asset = New-Asset $WindowsX64Url $WindowsX64Sha256
if ($null -ne $asset) { $windows["x86_64"] = $asset }
$asset = New-Asset $WindowsArm64Url $WindowsArm64Sha256
if ($null -ne $asset) { $windows["aarch64"] = $asset }

$macos = [ordered]@{}
$asset = New-Asset $MacX64Url $MacX64Sha256
if ($null -ne $asset) { $macos["x86_64"] = $asset }
$asset = New-Asset $MacArm64Url $MacArm64Sha256
if ($null -ne $asset) { $macos["aarch64"] = $asset }

$android = [ordered]@{}
$asset = New-Asset $AndroidX64Url $AndroidX64Sha256
if ($null -ne $asset) { $android["x86_64"] = $asset }
$asset = New-Asset $AndroidArm64Url $AndroidArm64Sha256
if ($null -ne $asset) { $android["aarch64"] = $asset }

$manifest = [ordered]@{
    version     = $Version
    release_url = $ReleaseUrl
    windows     = $windows
    macos       = $macos
    android     = $android
}

$json = $manifest | ConvertTo-Json -Depth 6
$parent = Split-Path -Parent $Output
if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($Output),
    $json,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Wrote $Output"
