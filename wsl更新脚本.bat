@echo off
chcp 936 >nul
echo 正在安装 WSL 更新...
set MSI_PATH=%~dp0wsl_update_x64.msi
if not exist "%MSI_PATH%" (
    echo 错误：找不到文件 %MSI_PATH%
    pause
    exit /b 1
)
msiexec /i "%MSI_PATH%" /quiet /norestart
if %errorlevel% == 0 (
    echo 安装成功！
) else (
    echo 安装失败，错误码：%errorlevel%
)
pause