@echo off
chcp 936 >nul
setlocal enabledelayedexpansion

:: ============================================================
::  OpenClaw 启动器 (Windows) - 优化版
::  用法: start.bat [--reload | --stop | --logs | --status]
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "IMAGE_NAME=ghcr.io/openclaw/openclaw:latest"
set "TAR_FILE=%SCRIPT_DIR%openclaw-image.tar"
set "COMPOSE_FILE=%SCRIPT_DIR%docker-compose.yml"
set "ENV_FILE=%SCRIPT_DIR%.env"
set "APP_URL=http://localhost:3000"
set "MIN_DISK_MB=2048"

:: ---------- 子命令分发 ----------
if /i "%~1"=="--stop"   goto :cmd_stop
if /i "%~1"=="--logs"   goto :cmd_logs
if /i "%~1"=="--status" goto :cmd_status
if /i "%~1"=="--help"   goto :cmd_help

echo.
echo ========================================
echo        OpenClaw 启动器 (Windows)
echo ========================================

:: ========== 第 1 步：检查 Docker 安装 ==========
echo.
echo [1/6] 正在检查 Docker 安装状态...
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 Docker，请先安装 Docker Desktop。
    echo        下载地址: https://www.docker.com/products/docker-desktop
    goto :fail
)
for /f "tokens=3" %%v in ('docker --version 2^>nul') do set "DOCKER_VER=%%v"
echo [成功] 已找到 Docker %DOCKER_VER%

:: ========== 第 2 步：检查 Docker 运行状态 ==========
echo.
echo [2/6] 正在检查 Docker 运行状态...
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo [警告] Docker 未运行，正在尝试启动 Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe" 2>nul
    echo        等待 Docker 启动中（最多 60 秒）...
    set "WAIT=0"
    :wait_docker
    if !WAIT! geq 60 (
        echo [错误] Docker 启动超时，请手动打开 Docker Desktop 后重试。
        goto :fail
    )
    timeout /t 3 /nobreak >nul
    set /a WAIT+=3
    docker info >nul 2>&1
    if %errorlevel% neq 0 goto :wait_docker
    echo [成功] Docker 已启动。
) else (
    echo [成功] Docker 正在运行。
)

:: ========== 第 3 步：检查磁盘空间 ==========
echo.
echo [3/6] 正在检查磁盘空间...
for /f "tokens=3" %%a in ('dir /-c "%SCRIPT_DIR%." 2^>nul ^| findstr /c:"可用字节"') do (
    set /a "FREE_MB=%%a / 1048576" 2>nul
)
if defined FREE_MB (
    if !FREE_MB! lss %MIN_DISK_MB% (
        echo [警告] 磁盘可用空间不足 %MIN_DISK_MB% MB（当前: !FREE_MB! MB），加载可能失败。
    ) else (
        echo [成功] 磁盘空间充足。
    )
) else (
    echo [信息] 无法检测磁盘空间，继续执行...
)

:: ========== 第 4 步：加载镜像 ==========
echo.
echo [4/6] 正在检查 Docker 镜像...
docker image inspect %IMAGE_NAME% >nul 2>&1
set "IMAGE_EXISTS=%errorlevel%"

if %IMAGE_EXISTS% neq 0 (
    echo [信息] 本地未找到镜像，准备从 tar 文件加载...
    goto :do_load
)
if /i "%~1"=="--reload" (
    echo [信息] 检测到 --reload 参数，正在重新加载镜像...
    goto :do_load
)
echo [成功] 镜像已就绪。如需更新请运行: start.bat --reload
goto :check_env

:do_load
if not exist "%TAR_FILE%" (
    echo [错误] 未找到镜像文件: %TAR_FILE%
    echo        请确保 openclaw-image.tar 与本脚本在同一目录下。
    goto :fail
)

:: 显示文件大小，给用户预期
for %%F in ("%TAR_FILE%") do (
    set "TAR_SIZE_BYTES=%%~zF"
    set /a "TAR_SIZE_MB=%%~zF / 1048576"
)
if !TAR_SIZE_MB! lss 10 (
    echo [错误] 镜像文件仅 !TAR_SIZE_MB! MB，文件可能不完整或已损坏。
    goto :fail
)
echo [信息] 镜像文件大小: !TAR_SIZE_MB! MB
echo [信息] 正在加载镜像，预计需要 1~5 分钟，请勿关闭窗口...

:: 使用临时文件捕获输出，同时显示进度动画
set "LOAD_LOG=%TEMP%\openclaw_load_%RANDOM%.log"
start /b cmd /c "docker load -i "%TAR_FILE%" >"%LOAD_LOG%" 2>&1 & echo DONE>>"%LOAD_LOG%""

set "SPIN=0"
set "ELAPSED=0"
:load_spin
set /a SPIN+=1
set /a MOD=SPIN %% 4
if !MOD!==0 set "CH=|"
if !MOD!==1 set "CH=/"
if !MOD!==2 set "CH=-"
if !MOD!==3 set "CH=\"
set /a "ELAPSED=SPIN * 2"

<nul set /p "=    [!CH!] 已等待 !ELAPSED! 秒...   " & echo. & <nul set /p "="

:: 检查是否完成
findstr /c:"DONE" "%LOAD_LOG%" >nul 2>&1
if %errorlevel%==0 goto :load_done

:: 超时检查（10 分钟 = 600 秒）
if !ELAPSED! geq 600 (
    echo.
    echo [错误] 镜像加载超时（已等待 10 分钟）。
    echo        可能原因: 文件损坏、Docker 资源不足。
    echo        请尝试: 重启 Docker Desktop 后再运行本脚本。
    taskkill /f /im "docker.exe" >nul 2>&1
    del "%LOAD_LOG%" >nul 2>&1
    goto :fail
)

timeout /t 2 /nobreak >nul
goto :load_spin

:load_done
echo.

:: 检查加载结果
findstr /c:"Loaded image" "%LOAD_LOG%" >nul 2>&1
if %errorlevel%==0 (
    echo [成功] 镜像加载完成。
) else (
    echo [错误] 镜像加载失败，详细信息:
    type "%LOAD_LOG%"
    del "%LOAD_LOG%" >nul 2>&1
    goto :fail
)
del "%LOAD_LOG%" >nul 2>&1

:: ========== 第 5 步：检查 .env 配置 ==========
:check_env
echo.
echo [5/6] 正在检查 .env 配置文件...

if exist "%ENV_FILE%" goto :check_env_content

:: 从模板创建 .env
set "ENV_TEMPLATE="
if exist "%SCRIPT_DIR%.env.example" set "ENV_TEMPLATE=%SCRIPT_DIR%.env.example"
if exist "%SCRIPT_DIR%env.example"  set "ENV_TEMPLATE=%SCRIPT_DIR%env.example"

if "%ENV_TEMPLATE%"=="" (
    echo [错误] 未找到 .env 或模板文件，请检查文件完整性。
    goto :fail
)
copy "%ENV_TEMPLATE%" "%ENV_FILE%" >nul
echo [警告] 已从模板创建 .env 文件。
echo        请在打开的记事本中填写 API Key，保存后重新运行本脚本。
notepad "%ENV_FILE%"
goto :end

:check_env_content
:: 检查文件是否为空
for %%A in ("%ENV_FILE%") do (
    if %%~zA==0 (
        echo [警告] .env 文件为空，请先填写配置信息。
        notepad "%ENV_FILE%"
        goto :end
    )
)

:: 检查是否包含未填写的占位符
findstr /r /c:"YOUR_.*_HERE" /c:"sk-xxx" /c:"=<" /c:"=$" "%ENV_FILE%" >nul 2>&1
if %errorlevel%==0 (
    echo [警告] .env 中似乎有未填写的配置项，请检查并补充。
    echo        按任意键打开编辑，或关闭窗口取消...
    pause >nul
    notepad "%ENV_FILE%"
    goto :end
)
echo [成功] 已找到 .env 配置文件。

:: ========== 第 6 步：启动服务 ==========
echo.
echo [6/6] 正在启动 OpenClaw...
cd /d "%SCRIPT_DIR%"

:: 先停止旧容器，避免冲突
docker compose down >nul 2>&1

docker compose up -d
if %errorlevel% neq 0 (
    echo.
    echo [错误] 启动失败，请查看上方报错信息。
    echo        常见原因:
    echo          - 端口 3000 被占用（用 netstat -ano ^| findstr :3000 查看）
    echo          - docker-compose.yml 文件有误
    echo          - .env 配置不正确
    goto :fail
)

:: 等待服务就绪
echo [信息] 等待服务就绪...
set "HEALTH_WAIT=0"
:health_loop
if !HEALTH_WAIT! geq 30 (
    echo [警告] 服务启动较慢，请稍后手动访问 %APP_URL%
    goto :success
)
timeout /t 2 /nobreak >nul
set /a HEALTH_WAIT+=2

curl -s -o nul -w "%%{http_code}" %APP_URL% 2>nul | findstr /c:"200" >nul 2>&1
if %errorlevel%==0 goto :success
goto :health_loop

:success
echo.
echo ========================================
echo   [成功] OpenClaw 已成功启动！
echo   浏览器访问: %APP_URL%
echo ========================================
echo.
echo   其他命令:
echo     start.bat --stop     停止服务
echo     start.bat --logs     查看日志
echo     start.bat --status   查看运行状态
echo     start.bat --reload   重新加载镜像
goto :end

:: ============================================================
::  子命令
:: ============================================================

:cmd_stop
echo.
echo [信息] 正在停止 OpenClaw...
cd /d "%SCRIPT_DIR%"
docker compose down
if %errorlevel%==0 (
    echo [成功] 服务已停止。
) else (
    echo [错误] 停止失败，请手动执行: docker compose down
)
goto :end

:cmd_logs
echo.
echo [信息] 正在获取日志（Ctrl+C 退出）...
cd /d "%SCRIPT_DIR%"
docker compose logs -f --tail=100
goto :end

:cmd_status
echo.
cd /d "%SCRIPT_DIR%"
echo [OpenClaw 容器状态]
echo.
docker compose ps
echo.
curl -s -o nul -w "HTTP状态: %%{http_code}" %APP_URL% 2>nul && echo  - 服务可访问 || echo  - 服务不可访问
echo.
goto :end

:cmd_help
echo.
echo 用法: start.bat [选项]
echo.
echo   (无参数)      正常启动 OpenClaw
echo   --reload      重新加载 Docker 镜像后启动
echo   --stop        停止所有服务
echo   --logs        查看实时日志
echo   --status      查看运行状态
echo   --help        显示此帮助信息
echo.
goto :end

:: ============================================================
::  退出处理
:: ============================================================

:fail
echo.
echo [!] 脚本执行失败，请查看上方错误信息。
echo     如需帮助，请将以上输出截图反馈。
pause
endlocal
exit /b 1

:end
echo.
pause
endlocal
exit /b 0