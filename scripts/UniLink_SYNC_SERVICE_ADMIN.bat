@echo off
setlocal
set SCRIPT_PATH=D:\agents\codex\hanako-control\client\rustdesk\scripts\sync_service_from_user_build_admin.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
pause
