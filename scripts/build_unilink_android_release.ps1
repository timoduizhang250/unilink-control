param(
    [string]$Flutter = "D:\tools\flutter\bin\flutter.bat",
    [string]$WslDistro = "Ubuntu",
    [string]$AndroidNdk = "/opt/android-sdk/ndk/28.2.13676358",
    [string]$VcpkgRoot = "/opt/vcpkg",
    [switch]$SkipRust
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterDir = Join-Path $repo "flutter"
$pubspec = Get-Content -Raw -Encoding UTF8 (Join-Path $flutterDir "pubspec.yaml")
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $versionMatch.Success) {
    throw "Could not read version and build number from flutter/pubspec.yaml"
}
$version = $versionMatch.Groups[1].Value
$buildNumber = $versionMatch.Groups[2].Value

$cargo = Get-Content -Raw -Encoding UTF8 (Join-Path $repo "Cargo.toml")
$cargoMatch = [regex]::Match($cargo, '(?m)^version\s*=\s*"([^"]+)"')
if (-not $cargoMatch.Success -or $cargoMatch.Groups[1].Value -ne $version) {
    throw "Cargo.toml and flutter/pubspec.yaml versions do not match"
}

$portableCargo = Get-Content -Raw -Encoding UTF8 (Join-Path $repo "libs\portable\Cargo.toml")
$portableMatch = [regex]::Match($portableCargo, '(?m)^version\s*=\s*"([^"]+)"')
if (-not $portableMatch.Success -or $portableMatch.Groups[1].Value -ne $version) {
    throw "libs/portable/Cargo.toml and flutter/pubspec.yaml versions do not match"
}

$keyPropertiesPath = Join-Path $flutterDir "android\key.properties"
if (-not (Test-Path -LiteralPath $keyPropertiesPath -PathType Leaf)) {
    throw "Missing flutter/android/key.properties release signing configuration"
}
$keyProperties = @{}
Get-Content -LiteralPath $keyPropertiesPath -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $keyProperties[$matches[1]] = $matches[2]
    }
}
if (-not $keyProperties.ContainsKey("storeFile") -or
    -not (Test-Path -LiteralPath $keyProperties["storeFile"] -PathType Leaf)) {
    throw "Android release keystore does not exist"
}

if (-not $SkipRust) {
    foreach ($value in @($AndroidNdk, $VcpkgRoot)) {
        if ($value -notmatch '^/[A-Za-z0-9._/-]+$') {
            throw "Unsafe WSL build path: $value"
        }
    }

    $repoForWsl = $repo.Replace('\', '/')
    $repoWsl = (& wsl.exe -d $WslDistro -- wslpath -a $repoForWsl).Trim()
    if ($LASTEXITCODE -ne 0 -or $repoWsl -notmatch '^/[A-Za-z0-9._/-]+$') {
        throw "Could not resolve the repository path in WSL"
    }
    $buildCommand = @"
set -e
cd '$repoWsl'
unset ANDROID_NDK_ROOT
export ANDROID_NDK_HOME='$AndroidNdk'
export VCPKG_ROOT='$VcpkgRoot'
export LC_ALL=C.UTF-8
cargo ndk --platform 21 --target aarch64-linux-android build --locked --release --features flutter,hwcodec
"@
    & wsl.exe -d $WslDistro -- bash -lc $buildCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Android Rust build failed"
    }

    $rustLibrary = Join-Path $repo "target\aarch64-linux-android\release\liblibrustdesk.so"
    if (-not (Test-Path -LiteralPath $rustLibrary -PathType Leaf)) {
        throw "Android Rust library was not produced"
    }
    & rg -a -F -q $version $rustLibrary
    if ($LASTEXITCODE -ne 0) {
        throw "Android Rust library does not contain version $version"
    }
    & rg -a -F -q "unilink-control-releases/releases/latest/download/latest.json" $rustLibrary
    if ($LASTEXITCODE -ne 0) {
        throw "Android Rust library does not contain the UniLink update endpoint"
    }
    Copy-Item -LiteralPath $rustLibrary -Destination (Join-Path $flutterDir "android\app\src\main\jniLibs\arm64-v8a\librustdesk.so") -Force
}

& $Flutter pub get --directory $flutterDir
if ($LASTEXITCODE -ne 0) {
    throw "Flutter dependency resolution failed"
}

Push-Location $flutterDir
try {
    & $Flutter build apk --release --no-pub --target-platform android-arm64 --build-name $version --build-number $buildNumber
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Android release build failed"
    }
} finally {
    Pop-Location
}

$sourceApk = Join-Path $flutterDir "build\app\outputs\flutter-apk\app-release.apk"
$releaseDir = Join-Path $flutterDir "build\releases"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$releaseApk = Join-Path $releaseDir "UniLink-Control-$version-android-arm64.apk"
Copy-Item -LiteralPath $sourceApk -Destination $releaseApk -Force

$buildTools = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools") -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if ($null -eq $buildTools) {
    throw "Android SDK build tools are missing"
}
$badging = & (Join-Path $buildTools.FullName "aapt.exe") dump badging $releaseApk
if ($LASTEXITCODE -ne 0 -or
    $badging[0] -notmatch "name='com\.unilink\.control'" -or
    $badging[0] -notmatch "versionCode='$buildNumber'" -or
    $badging[0] -notmatch "versionName='$([regex]::Escape($version))'") {
    throw "Built APK package or version verification failed"
}
$signing = (& (Join-Path $buildTools.FullName "apksigner.bat") verify --print-certs $releaseApk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $signing -notmatch 'CN\s*=\s*UniLink Control') {
    throw "Built APK signing verification failed"
}

$sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseApk).Hash.ToLowerInvariant()
Write-Host "Android release built: $releaseApk"
Write-Host "Version: $version ($buildNumber)"
Write-Host "SHA-256: $sha256"
