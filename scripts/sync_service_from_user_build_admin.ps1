param(
    [string]$UserInstall = "$env:LOCALAPPDATA\Programs\UniLink Control",
    [string]$ServiceInstall = "$env:ProgramFiles\UniLink Control"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script as Administrator."
    }
}

Assert-Admin

if (-not (Test-Path -LiteralPath $UserInstall)) {
    throw "User install not found: $UserInstall"
}
if (-not (Test-Path -LiteralPath $ServiceInstall)) {
    throw "Service install not found: $ServiceInstall"
}

$resolvedUser = (Resolve-Path -LiteralPath $UserInstall).Path
$resolvedService = (Resolve-Path -LiteralPath $ServiceInstall).Path
if ($resolvedService -notlike "$env:ProgramFiles\UniLink Control*") {
    throw "Refusing to write outside UniLink Program Files directory: $resolvedService"
}

Write-Host "Stopping UniLink Control service..."
Stop-Service -Name "UniLink Control" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Get-Process | Where-Object { $_.ProcessName -eq "UniLink Control" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Copying user build to service install..."
robocopy $resolvedUser $resolvedService /MIR /XD "Uninstall UniLink Control.lnk" /R:2 /W:1 /NFL /NDL /NP
$code = $LASTEXITCODE
if ($code -ge 8) {
    throw "robocopy failed with exit code $code"
}

Write-Host "Refreshing required options..."
& "$resolvedService\UniLink Control.exe" --option verification-method use-both-passwords
& "$resolvedService\UniLink Control.exe" --option temporary-password-length 6
& "$resolvedService\UniLink Control.exe" --option stop-service N
& "$resolvedService\UniLink Control.exe" --option allow-websocket N
& "$resolvedService\UniLink Control.exe" --option local-ip-addr ""

Write-Host "Starting UniLink Control service..."
Start-Service -Name "UniLink Control"
Start-Sleep -Seconds 2

Write-Host "Launching service-matched app..."
Start-Process -FilePath "$resolvedService\UniLink Control.exe"

Write-Host "Done. If the one-time password still says generating, close and reopen UniLink Control once."
