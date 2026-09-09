@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo 将删除计划任务和 %%LOCALAPPDATA%%\DSTDailyGift。
echo.
set /p "KEEP=是否把运行日志备份到桌面？(Y/N) [Y]: "
if "%KEEP%"=="" set "KEEP=Y"
if /I "%KEEP%"=="Y" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" -KeepLogs
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
)
echo.
pause
