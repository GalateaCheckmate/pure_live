@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0"
if errorlevel 1 goto :repo_failed

where fvm >nul 2>nul
if not errorlevel 1 (
    set "FLUTTER_CMD=fvm flutter"
    echo [PureLive] 检测到 FVM，将使用 fvm flutter。
) else (
    where flutter >nul 2>nul
    if errorlevel 1 goto :flutter_missing
    set "FLUTTER_CMD=flutter"
    echo [PureLive] 未检测到 FVM，将使用系统 flutter。
)

echo.
echo [PureLive] 正在获取依赖...
call %FLUTTER_CMD% pub get
if errorlevel 1 goto :pub_get_failed

echo.
echo [PureLive] 正在启动 Windows 版本...
call %FLUTTER_CMD% run -d windows
if errorlevel 1 goto :run_failed

echo.
echo [PureLive] 本地运行已结束。
pause
exit /b 0

:repo_failed
echo.
echo [PureLive] 无法进入仓库目录：%~dp0
echo 请确认脚本仍位于 PureLive 仓库根目录。
pause
exit /b 1

:flutter_missing
echo.
echo [PureLive] 未找到 FVM 或 Flutter。
echo 请先安装 FVM，或将 Flutter 添加到系统 PATH 后重试。
pause
exit /b 1

:pub_get_failed
echo.
echo [PureLive] 依赖获取失败，未启动应用。
echo 请检查网络、Flutter 环境和依赖配置后重试。
pause
exit /b 1

:run_failed
echo.
echo [PureLive] Windows 版本启动失败。
echo 请查看上方错误信息，修复后重新双击此脚本。
pause
exit /b 1
