Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$vcvarsCandidates = @(
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
)

$vcvars = $vcvarsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vcvars) {
    throw "Visual Studio vcvars64.bat was not found. Install Visual Studio 2022 Build Tools with Desktop development with C++."
}

$pythonCandidates = @(
    $env:PYTHON,
    (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
    (Join-Path $env:LOCALAPPDATA "Python\pythoncore-3.14-64\python.exe"),
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe")
) | Where-Object { $_ -and (Test-Path $_) }

$python = $pythonCandidates | Where-Object {
    & $_ -m pip --version *> $null
    $LASTEXITCODE -eq 0
} | Select-Object -First 1
if (-not $python) {
    throw "Python was not found. Set PYTHON to python.exe or install Python."
}

$vcpkgCandidates = @(
    $env:VCPKG_ROOT,
    "D:\tools\vcpkg",
    "C:\vcpkg"
) | Where-Object { $_ -and (Test-Path (Join-Path $_ "installed\x64-windows-static")) }
$vcpkgRoot = $vcpkgCandidates | Select-Object -First 1
if (-not $vcpkgRoot) {
    throw "vcpkg x64-windows-static dependencies were not found."
}

$pubspec = Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot "flutter\pubspec.yaml")
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $versionMatch.Success) {
    throw "Could not read the UniLink version from flutter/pubspec.yaml."
}
$version = $versionMatch.Groups[1].Value
$expectedProductVersion = "$version+$($versionMatch.Groups[2].Value)"

$buildCommand = "`"$vcvars`" && set VCPKG_ROOT=$vcpkgRoot&& set VCPKG_INSTALLED_ROOT=$vcpkgRoot\installed&& set VCPKG_DEFAULT_TRIPLET=x64-windows-static&& `"$python`" build.py --flutter"
cmd.exe /d /c $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "User build update failed with exit code $LASTEXITCODE."
}

$installer = Join-Path $RepoRoot "rustdesk-$version-install.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "The UniLink installer was not produced: $installer"
}

$installedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles "UniLink Control"))
$installedExe = [IO.Path]::GetFullPath((Join-Path $installedRoot "UniLink Control.exe"))
if (-not $installedExe.StartsWith($installedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to install outside the UniLink Program Files directory."
}

$installerProcess = Start-Process -FilePath $installer -ArgumentList "--silent-install" -Verb RunAs -WindowStyle Hidden -PassThru
if (-not $installerProcess.WaitForExit(180000)) {
    throw "The UniLink installer did not exit within 3 minutes."
}
if ($installerProcess.ExitCode -ne 0) {
    throw "The UniLink installer exited with code $($installerProcess.ExitCode)."
}

$deadline = (Get-Date).AddMinutes(3)
do {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $installedExe -PathType Leaf) {
        $actualVersion = (Get-Item -LiteralPath $installedExe).VersionInfo.ProductVersion
        if ($actualVersion -eq $expectedProductVersion) {
            break
        }
    }
} while ((Get-Date) -lt $deadline)

if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
    throw "The Program Files UniLink executable is missing after installation."
}
$actualVersion = (Get-Item -LiteralPath $installedExe).VersionInfo.ProductVersion
if ($actualVersion -ne $expectedProductVersion) {
    throw "Installed UniLink version mismatch: expected $expectedProductVersion, got $actualVersion."
}

$service = Get-CimInstance Win32_Service -Filter "Name='UniLink Control'" -ErrorAction SilentlyContinue
if ($null -eq $service -or $service.PathName -notlike "*$installedExe*") {
    throw "The UniLink service does not point to the Program Files installation."
}

Start-Process -FilePath $installedExe
Write-Host "UniLink Control $actualVersion installed in $installedRoot"
