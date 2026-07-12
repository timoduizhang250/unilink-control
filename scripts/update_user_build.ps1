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
    (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe")
) | Where-Object { $_ -and (Test-Path $_) }

$python = $pythonCandidates | Select-Object -First 1
if (-not $python) {
    throw "Python was not found. Set PYTHON to python.exe or install Python."
}

$buildCommand = "`"$vcvars`" && `"$python`" build.py --flutter --skip-portable-pack --install-user --launch"
cmd.exe /d /c $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "User build update failed with exit code $LASTEXITCODE."
}
