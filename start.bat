@echo off
chcp 936 >nul
setlocal enabledelayedexpansion

:: ============================================================
::  OpenClaw 一键部署 (Windows) - 启动脚本
::  用法: start.bat [--reload | --stop | --logs | --status | --help]
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "IMAGE_NAME=ghcr.io/openclaw/openclaw:latest"
set "TAR_FILE=%SCRIPT_DIR%openclaw-image.tar"
set "COMPOSE_FILE=%SCRIPT_DIR%docker-compose.yml"
set "ENV_FILE=%SCRIPT_DIR%.env"
set "APP_URL=http://localhost:18789"
set "MIN_DISK_MB=2048"

:: ---------- 命令分发 ----------
if /i "%~1"=="--stop"   goto :cmd_stop
if /i "%~1"=="--logs"   goto :cmd_logs
if /i "%~1"=="--status" goto :cmd_status
if /i "%~1"=="--help"   goto :cmd_help

echo.
echo ========================================
echo        OpenClaw 一键部署 (Windows)
echo 项目地址：   https://github.com/zhangsanxueai/PocketClaw  
echo  出品方 三学 Ai 
echo  小助手： 三学 Ai  Raffy（助手）
echo ========================================

:: ========== 第 1 步：检查 Docker 安装 ==========
echo.
echo [1/7] 正在检查 Docker 安装状态...
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
echo [2/7] 正在检查 Docker 运行状态...
docker info >nul 2>&1
if %errorlevel% neq 0 (
    :: 先检查 Docker Desktop 进程是否存在但尚未就绪，避免重复启动导致 backend.lock 冲突
    tasklist /fi "imagename eq Docker Desktop.exe" 2>nul | findstr /i "Docker Desktop.exe" >nul 2>&1
    if %errorlevel% neq 0 (
        echo [提示] Docker 未运行，正在启动 Docker Desktop...
        start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe" 2>nul
    ) else (
        echo [提示] Docker Desktop 进程已存在但未完全就绪，等待启动...
    )
    echo        等待 Docker 启动完成（最多 60 秒）...
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
    echo [成功] Docker 已经就绪
) else (
    echo [成功] Docker 正在运行。
)

:: ========== 第 3 步：检查磁盘空间 ==========
echo.
echo [3/7] 正在检查磁盘空间...
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

:: ========== 第 4 步：检查/加载镜像 ==========
echo.
echo [4/7] 正在检查 Docker 镜像...
docker image inspect %IMAGE_NAME% >nul 2>&1
set "IMAGE_EXISTS=%errorlevel%"

if /i "%~1"=="--reload" (
    echo [信息] 检测到 --reload 参数，将强制重新加载镜像...
    goto :do_load
)
if %IMAGE_EXISTS% neq 0 (
    echo [信息] 镜像未找到，准备从 tar 文件加载...
    goto :do_load
)
echo [成功] 镜像已经存在。如需重新加载: start.bat --reload
goto :check_env

:do_load
if not exist "%TAR_FILE%" (
    echo [错误] 未找到镜像文件: %TAR_FILE%
    echo        请确保 openclaw-image.tar 与本脚本在同一目录下。
    goto :fail
)

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
<nul set /p "=    [!CH!] 已等待 !ELAPSED! 秒...   "
echo.
findstr /c:"DONE" "%LOAD_LOG%" >nul 2>&1
if %errorlevel%==0 goto :load_done
if !ELAPSED! geq 600 (
    echo.
    echo [错误] 加载镜像超时（已超过 10 分钟）。
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
findstr /c:"Loaded image" "%LOAD_LOG%" >nul 2>&1
if %errorlevel%==0 (
    echo [成功] 镜像加载成功。
) else (
    echo [错误] 镜像加载失败，详细日志如下:
    type "%LOAD_LOG%"
    del "%LOAD_LOG%" >nul 2>&1
    goto :fail
)
del "%LOAD_LOG%" >nul 2>&1

:: ========== 第 5 步：检查 .env 配置文件 ==========
:check_env
echo.
echo [5/7] 正在检查 .env 配置文件...

if exist "%ENV_FILE%" goto :check_env_content

set "ENV_TEMPLATE="
if exist "%SCRIPT_DIR%.env.example" set "ENV_TEMPLATE=%SCRIPT_DIR%.env.example"
if exist "%SCRIPT_DIR%env.example"  set "ENV_TEMPLATE=%SCRIPT_DIR%env.example"

if "%ENV_TEMPLATE%"=="" (
    echo [错误] 未找到 .env 或模板文件，请检查文件完整性。
    goto :fail
)
copy "%ENV_TEMPLATE%" "%ENV_FILE%" >nul
echo [提示] 已从模板创建 .env 文件。
echo        请在打开的记事本中填写 API Key，保存后关闭即可继续。
notepad "%ENV_FILE%"
goto :end

:check_env_content
for %%A in ("%ENV_FILE%") do (
    if %%~zA==0 (
        echo [警告] .env 文件为空，请填写配置信息。
        notepad "%ENV_FILE%"
        goto :end
    )
)
findstr /r /c:"YOUR_.*_HERE" /c:"sk-xxx" /c:"=<" /c:"=$" "%ENV_FILE%" >nul 2>&1
if %errorlevel%==0 (
    echo [警告] .env 中可能含有未填写的占位符（请仔细检查）。
)
echo [成功] 已找到 .env 配置文件。

:: ========== 第 6 步：初始化设置 ==========
echo.
echo [6/7] 正在检查初始化状态...

cd /d "%SCRIPT_DIR%"

set "CFG_DIR="
set "WS_DIR="
for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
    if "%%a"=="OPENCLAW_CONFIG_DIR"    if not "%%b"=="" set "CFG_DIR=%%b"
    if "%%a"=="OPENCLAW_WORKSPACE_DIR" if not "%%b"=="" set "WS_DIR=%%b"
)

if "!CFG_DIR!"=="" (
    set "CFG_DIR=%SCRIPT_DIR%data\config"
    set "WS_DIR=%SCRIPT_DIR%data\workspace"
) else (
    set "CFG_DIR=!CFG_DIR:/=\!"
    if "!WS_DIR!"=="" set "WS_DIR=!CFG_DIR!\workspace"
    set "WS_DIR=!WS_DIR:/=\!"
)

if exist "!CFG_DIR!\openclaw.json" (
    echo [成功] 已检测到历史配置，将保留历史配置运行。
    goto :start_services
)

echo [信息] 首次运行，开始执行初始化设置（共 6 个步骤）...

:: 6.1 创建数据目录结构
echo.
echo [6.1] 正在创建数据目录结构...
mkdir "!CFG_DIR!" >nul 2>&1
mkdir "!WS_DIR!" >nul 2>&1
mkdir "!CFG_DIR!\identity" >nul 2>&1
mkdir "!CFG_DIR!\agents\main\agent" >nul 2>&1
mkdir "!CFG_DIR!\agents\main\sessions" >nul 2>&1
echo [成功] 数据目录创建完成。

:: 6.2 生成 Gateway Token（优先使用 PowerShell 密码学随机）
echo.
echo [6.2] 正在生成 Gateway Token...
set "NEW_TOKEN="
for /f "delims=" %%t in ('powershell -NoProfile -Command "$b=New-Object byte[] 32;[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($b);'oc'+(-join($b|ForEach-Object{$_.ToString('x2')}))" 2^>nul') do set "NEW_TOKEN=%%t"
if "!NEW_TOKEN!"=="" (
    :: 备用方案：时间戳 + 多个 RANDOM 拼接（优于纯 RANDOM 防碰撞）
    echo [警告] PowerShell 生成 Token 失败，使用备用方案...
    for /f "tokens=1-3 delims=:." %%a in ("%TIME%") do set "TS=%%a%%b%%c"
    set "NEW_TOKEN=oc!TS!%RANDOM%%RANDOM%%RANDOM%"
)
echo [成功] Gateway Token 已生成: !NEW_TOKEN!

:: 6.3 更新 .env 变量（先过滤旧值，再追加新值，避免重复覆盖）
echo.
echo [6.3] 正在更新 .env 配置...

set "ENV_KEYS=OPENCLAW_CONFIG_DIR OPENCLAW_WORKSPACE_DIR OPENCLAW_GATEWAY_PORT OPENCLAW_BRIDGE_PORT OPENCLAW_GATEWAY_BIND OPENCLAW_GATEWAY_TOKEN OPENCLAW_IMAGE OPENCLAW_EXTRA_MOUNTS OPENCLAW_HOME_VOLUME OPENCLAW_DOCKER_APT_PACKAGES OPENCLAW_EXTENSIONS OPENCLAW_SANDBOX OPENCLAW_DOCKER_SOCKET DOCKER_GID OPENCLAW_INSTALL_DOCKER_CLI OPENCLAW_ALLOW_INSECURE_PRIVATE_WS OPENCLAW_TZ"

set "ENV_TMP=%ENV_FILE%.tmp"
if exist "%ENV_TMP%" del "%ENV_TMP%"

(for /f "usebackq delims=" %%L in ("%ENV_FILE%") do (
    set "LINE=%%L"
    set "SKIP="
    for %%K in (%ENV_KEYS%) do (
        if not defined SKIP (
            for /f "tokens=1 delims==" %%A in ("%%L") do (
                if "%%A"=="%%K" set "SKIP=1"
            )
        )
    )
    if not defined SKIP echo(!LINE!
)) > "%ENV_TMP%"

move /y "%ENV_TMP%" "%ENV_FILE%" >nul

>> "%ENV_FILE%" (
    echo OPENCLAW_CONFIG_DIR=!CFG_DIR!
    echo OPENCLAW_WORKSPACE_DIR=!WS_DIR!
    echo OPENCLAW_GATEWAY_PORT=18789
    echo OPENCLAW_BRIDGE_PORT=18790
    echo OPENCLAW_GATEWAY_BIND=lan
    echo OPENCLAW_GATEWAY_TOKEN=!NEW_TOKEN!
    echo OPENCLAW_IMAGE=%IMAGE_NAME%
    echo OPENCLAW_EXTRA_MOUNTS=
    echo OPENCLAW_HOME_VOLUME=
    echo OPENCLAW_DOCKER_APT_PACKAGES=
    echo OPENCLAW_EXTENSIONS=
    echo OPENCLAW_SANDBOX=
    echo OPENCLAW_DOCKER_SOCKET=
    echo DOCKER_GID=
    echo OPENCLAW_INSTALL_DOCKER_CLI=
    echo OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=
    echo OPENCLAW_TZ=
)
echo [成功] .env 配置更新完成。

:: 6.4 修复数据目录权限
echo.
echo [6.4] 正在修复数据目录权限...
docker compose -f "%COMPOSE_FILE%" run --rm --user root --entrypoint sh openclaw-cli -c "find /home/node/.openclaw -xdev -exec chown node:node {} + ; [ -d /home/node/.openclaw/workspace/.openclaw ] && chown -R node:node /home/node/.openclaw/workspace/.openclaw || true"
if %errorlevel% neq 0 (
    echo [警告] 权限修复执行异常，继续尝试初始化...
) else (
    echo [成功] 数据目录权限修复完成。
)

:: 6.5 写入最小配置（确保首次启动式引导）
echo.
echo [6.5] 正在写入初始配置（最小化配置，保留引导式引导）...
set "OC_JSON=!CFG_DIR!\openclaw.json"
powershell -NoProfile -Command "Set-Content -Path '!OC_JSON!' -Value '{\"gateway\":{\"mode\":\"local\",\"bind\":\"lan\"}}' -Encoding UTF8" 2>nul
if not exist "!OC_JSON!" (
    (echo {"gateway":{"mode":"local","bind":"lan"}})>"!OC_JSON!" 2>nul
)
if not exist "!OC_JSON!" (
    echo [错误] 无法创建 openclaw.json，请检查目录权限。
    goto :fail
)
docker compose -f "%COMPOSE_FILE%" run --rm --user root --entrypoint sh openclaw-cli -c "chown node:node /home/node/.openclaw/openclaw.json 2>/dev/null || true" >nul 2>&1
echo [成功] 最小配置文件已创建（保留首次启动式引导）。

:: 6.6 固定 gateway 配置
echo.
echo [6.6] 正在固定 gateway 配置...
docker compose -f "%COMPOSE_FILE%" run --rm openclaw-cli config set gateway.mode local >nul 2>&1
if %errorlevel% neq 0 (
    echo [警告] 设置 gateway.mode 失败，继续执行...
)
docker compose -f "%COMPOSE_FILE%" run --rm openclaw-cli config set gateway.bind lan >nul 2>&1
if %errorlevel% neq 0 (
    echo [警告] 设置 gateway.bind 失败，继续执行...
)
echo [成功] gateway 配置固定完成。

echo.
echo [提示] 如需进一步引导设置（如配置 AI 服务商、频道等），请：
echo        - AI Provider:  openclaw onboard --auth-choice openai
echo        - 频道配置:     openclaw channels add --channel telegram --token ^<TOKEN^>
echo        - 完整引导:     openclaw onboard
echo        以上命令均可通过 docker compose run 执行。

echo.
echo ========================================
echo   [成功] 初始化完成！
echo   Token: !NEW_TOKEN!
echo   配置目录: !CFG_DIR!
echo   工作目录: !WS_DIR!
echo ========================================

:: ========== 第 7 步：启动服务 ==========
:start_services
echo.
echo [7/7] 正在启动 OpenClaw...
cd /d "%SCRIPT_DIR%"

:: ---- 确保每次启动前 .env 含有目录变量（防止丢失） ----
set "ENV_HAS_CFG="
set "ENV_HAS_WS="
for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
    if "%%a"=="OPENCLAW_CONFIG_DIR"    if not "%%b"=="" set "ENV_HAS_CFG=1"
    if "%%a"=="OPENCLAW_WORKSPACE_DIR" if not "%%b"=="" set "ENV_HAS_WS=1"
)
if not defined ENV_HAS_CFG (
    >> "%ENV_FILE%" echo OPENCLAW_CONFIG_DIR=%SCRIPT_DIR%data\config
    echo [信息] 已自动补写 OPENCLAW_CONFIG_DIR 到 .env
)
if not defined ENV_HAS_WS (
    >> "%ENV_FILE%" echo OPENCLAW_WORKSPACE_DIR=%SCRIPT_DIR%data\workspace
    echo [信息] 已自动补写 OPENCLAW_WORKSPACE_DIR 到 .env
)
:: ---- 补写结束 ----


set "ENV_CUR_IMAGE="
for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
    if "%%a"=="OPENCLAW_IMAGE" set "ENV_CUR_IMAGE=%%b"
)
if not "!ENV_CUR_IMAGE!"=="%IMAGE_NAME%" (
    set "ENV_TMP=%ENV_FILE%.tmp"
    if exist "!ENV_TMP!" del "!ENV_TMP!"
    (for /f "usebackq delims=" %%L in ("%ENV_FILE%") do (
        set "LINE=%%L"
        set "IS_IMG="
        for /f "tokens=1 delims==" %%A in ("%%L") do (
            if "%%A"=="OPENCLAW_IMAGE" set "IS_IMG=1"
        )
        if defined IS_IMG (
            echo OPENCLAW_IMAGE=%IMAGE_NAME%
        ) else (
            echo(!LINE!
        )
    )) > "!ENV_TMP!"
    if not defined ENV_CUR_IMAGE (
        >> "!ENV_TMP!" echo OPENCLAW_IMAGE=%IMAGE_NAME%
    )
    move /y "!ENV_TMP!" "%ENV_FILE%" >nul
    echo [信息] 已自动更新 OPENCLAW_IMAGE 为 %IMAGE_NAME%
)

docker compose down >nul 2>&1

docker compose up -d
if %errorlevel% neq 0 (
    echo.
    echo [错误] 启动失败，请查看上方日志了解详情。
    echo        常见原因:
    echo          - 端口 18789 被占用（用 netstat -ano ^| findstr :18789 查看）
    echo          - docker-compose.yml 文件损坏
    echo          - .env 配置不正确
    goto :fail
)

:: 等待服务健康检查（curl 或 Windows 下 PowerShell 替代）
echo [信息] 等待服务就绪...
set "HEALTH_WAIT=0"
:health_loop
if !HEALTH_WAIT! geq 30 (
    echo [警告] 健康检查超时，请手动访问 %APP_URL%
    goto :open_browser
)
timeout /t 2 /nobreak >nul
set /a HEALTH_WAIT+=2

:: 优先用 curl，不存在则用 PowerShell 替代
curl -s -o nul -w "%%{http_code}" %APP_URL% 2>nul | findstr /c:"200" >nul 2>&1
if %errorlevel%==0 goto :open_browser

powershell -NoProfile -Command "try{$r=(Invoke-WebRequest -Uri '%APP_URL%' -TimeoutSec 2 -UseBasicParsing).StatusCode;if($r -eq 200){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
if %errorlevel%==0 goto :open_browser

goto :health_loop

:: ========== 自动打开带 Token 的配对页面（避免 pairing required）==========
:open_browser
echo.
echo ========================================
echo   [成功] OpenClaw 已成功启动！
echo   访问地址: %APP_URL%
echo ========================================

:: 从 .env 读取当前 Token
set "CURRENT_TOKEN="
for /f "usebackq tokens=1,* delims==" %%a in ("%ENV_FILE%") do (
    if "%%a"=="OPENCLAW_GATEWAY_TOKEN" if not "%%b"=="" set "CURRENT_TOKEN=%%b"
)

if not "!CURRENT_TOKEN!"=="" (
    echo.
    echo [信息] 正在自动打开配对页面...
    :: 将 token 拼入 URL，自动完成配对，避免手动输入 pairing required。
    set "DASHBOARD_URL=%APP_URL%?wsUrl=ws%%3A%%2F%%2Flocalhost%%3A18789&token=!CURRENT_TOKEN!"
    start "" "!DASHBOARD_URL!"
    echo [成功] 浏览器已打开完整 URL。
    echo        如未自动打开，请手动访问:
    echo        !DASHBOARD_URL!
) else (
    start "" "%APP_URL%"
    echo [信息] 未获取到 Token，已打开配对首页，请手动输入 Token 配对。
)

echo.
echo   常用命令:
echo     start.bat --stop     停止服务
echo     start.bat --logs     查看日志
echo     start.bat --status   查看服务状态
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
echo [OpenClaw 服务状态]
echo.
docker compose ps
echo.
curl -s -o nul -w "HTTP状态: %%{http_code}" %APP_URL% 2>nul && echo  - 服务可访问 || (
    powershell -NoProfile -Command "try{$r=(Invoke-WebRequest -Uri '%APP_URL%' -TimeoutSec 3 -UseBasicParsing).StatusCode;Write-Host 'HTTP状态:' $r '- 服务可访问'}catch{Write-Host '服务暂不可访问'}" 2>nul
)
echo.
goto :end

:cmd_help
echo.
echo 用法: start.bat [选项]
echo.
echo   (无参数)      首次运行 OpenClaw（首次运行将自动初始化设置）
echo   --reload      重新加载 Docker 镜像文件
echo   --stop        停止所有服务
echo   --logs        查看实时日志
echo   --status      查看服务状态
echo   --help        显示此帮助信息
echo.
goto :end

:: ============================================================
::  退出处理
:: ============================================================

:fail
echo.
echo [!] 脚本执行失败，请查看上方日志了解详情。
echo     如需帮助请截图以上内容。
pause
endlocal
exit /b 1

:end
echo.
pause
endlocal
exit /b 0
