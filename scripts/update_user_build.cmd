@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_user_build.ps1"
if errorlevel 1 (
  echo.
  echo UniLink Control update failed. See the messages above.
  pause
)
