@echo off
chcp 65001 >nul
set SCRIPT_DIR=%~dp0
echo ▶ 正在停止 OpenClaw...
cd /d "%SCRIPT_DIR%"
docker compose down
echo ✅ 已停止
pause
