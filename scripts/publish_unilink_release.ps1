param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Repo = "timoduizhang250/unilink-control-releases",
    [string]$WindowsX64 = "",
    [string]$MacX64 = "",
    [string]$MacArm64 = "",
    [string]$AndroidX64 = "",
    [string]$AndroidArm64 = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$releaseUrl = "https://github.com/$Repo/releases/tag/$Version"

function Asset-Url($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    $name = Split-Path -Leaf $Path
    return "https://github.com/$Repo/releases/download/$Version/$name"
}

function Asset-Sha256($Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ""
    }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-AssetPath($Path, $Name) {
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name asset does not exist: $Path"
    }
}

Assert-AssetPath $WindowsX64 "Windows x86_64"
Assert-AssetPath $MacX64 "macOS x86_64"
Assert-AssetPath $MacArm64 "macOS aarch64"
Assert-AssetPath $AndroidX64 "Android x86_64"
Assert-AssetPath $AndroidArm64 "Android aarch64"

$manifestArgs = @(
    "-Version", $Version,
    "-ReleaseUrl", $releaseUrl,
    "-Output", "latest.json"
)

if (-not [string]::IsNullOrWhiteSpace($WindowsX64)) {
    $manifestArgs += @(
        "-WindowsX64Url", (Asset-Url $WindowsX64),
        "-WindowsX64Sha256", (Asset-Sha256 $WindowsX64)
    )
}
if (-not [string]::IsNullOrWhiteSpace($MacX64)) {
    $manifestArgs += @(
        "-MacX64Url", (Asset-Url $MacX64),
        "-MacX64Sha256", (Asset-Sha256 $MacX64)
    )
}
if (-not [string]::IsNullOrWhiteSpace($MacArm64)) {
    $manifestArgs += @(
        "-MacArm64Url", (Asset-Url $MacArm64),
        "-MacArm64Sha256", (Asset-Sha256 $MacArm64)
    )
}
if (-not [string]::IsNullOrWhiteSpace($AndroidX64)) {
    $manifestArgs += @(
        "-AndroidX64Url", (Asset-Url $AndroidX64),
        "-AndroidX64Sha256", (Asset-Sha256 $AndroidX64)
    )
}
if (-not [string]::IsNullOrWhiteSpace($AndroidArm64)) {
    $manifestArgs += @(
        "-AndroidArm64Url", (Asset-Url $AndroidArm64),
        "-AndroidArm64Sha256", (Asset-Sha256 $AndroidArm64)
    )
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\generate_unilink_update_manifest.ps1" @manifestArgs

$assets = [System.Collections.Generic.List[string]]::new()
foreach ($path in @($WindowsX64, $MacX64, $MacArm64, $AndroidX64, $AndroidArm64, "latest.json")) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and
        (Test-Path -LiteralPath $path -PathType Leaf) -and
        -not $assets.Contains($path)) {
        $assets.Add($path)
    }
}

gh release view $Version --repo $Repo *> $null
if ($LASTEXITCODE -ne 0) {
    gh release create $Version --repo $Repo --title "UniLink Control $Version" --notes "UniLink Control release $Version."
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub release $Version"
    }
}

gh release upload $Version @assets --repo $Repo --clobber
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload GitHub release assets for $Version"
}
Write-Host "Published $releaseUrl"
