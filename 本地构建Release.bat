@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0"
if errorlevel 1 goto :repo_failed

set "BUILD_DIR=%CD%\build\windows\x64\runner\Release"
set "OUTPUT_DIR=%CD%\PureLive-Local"
set "TEMP_DIR=%CD%\PureLive-Local.__new"
set "ZIP_PATH=%CD%\PureLive-Windows.zip"
set "PURELIVE_OUTPUT_DIR=%OUTPUT_DIR%"
set "PURELIVE_ZIP_PATH=%ZIP_PATH%"

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
echo [PureLive] 正在构建 Windows Release 版本...
call %FLUTTER_CMD% build windows --release
if errorlevel 1 goto :build_failed

if not exist "%BUILD_DIR%\pure_live.exe" goto :output_missing

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"
if errorlevel 1 goto :copy_failed

xcopy "%BUILD_DIR%\*" "%TEMP_DIR%\" /E /I /H /Y /Q >nul
if errorlevel 1 goto :copy_failed

if exist "%OUTPUT_DIR%" (
    echo.
    echo [PureLive] 正在覆盖旧的 PureLive-Local...
    rmdir /s /q "%OUTPUT_DIR%"
    if exist "%OUTPUT_DIR%" goto :replace_failed
)

move "%TEMP_DIR%" "%OUTPUT_DIR%" >nul
if errorlevel 1 goto :replace_failed

if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path (Join-Path $env:PURELIVE_OUTPUT_DIR '*') -DestinationPath $env:PURELIVE_ZIP_PATH -Force"
if errorlevel 1 goto :zip_failed

echo.
echo ============================================================
echo [PureLive] Release 构建完成。
echo [PureLive] 固定运行目录：%OUTPUT_DIR%
echo [PureLive] 固定压缩包：%ZIP_PATH%
echo [PureLive] 下次运行本脚本会直接覆盖这两个旧输出。
echo ============================================================
echo.
echo 可直接运行：%OUTPUT_DIR%\pure_live.exe
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
echo [PureLive] 依赖获取失败，未开始 Release 构建。
echo 旧的 PureLive-Local 不会被删除。
pause
exit /b 1

:build_failed
echo.
echo [PureLive] Release 构建失败。
echo 旧的 PureLive-Local 不会被删除。
echo 请查看上方错误信息后重试。
pause
exit /b 1

:output_missing
echo.
echo [PureLive] Flutter 报告构建完成，但没有找到：
echo %BUILD_DIR%\pure_live.exe
echo 旧的 PureLive-Local 不会被删除。
pause
exit /b 1

:copy_failed
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
echo.
echo [PureLive] 无法整理新的 Release 文件。
echo 旧的 PureLive-Local 不会被删除。
pause
exit /b 1

:replace_failed
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
echo.
echo [PureLive] 无法覆盖旧的 PureLive-Local。
echo 请确认旧版 pure_live.exe 已完全退出，再重新运行脚本。
pause
exit /b 1

:zip_failed
echo.
echo [PureLive] PureLive-Local 已成功更新，但 ZIP 压缩失败。
echo 你仍然可以直接运行：%OUTPUT_DIR%\pure_live.exe
pause
exit /b 1
