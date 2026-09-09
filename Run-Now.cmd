@echo off
chcp 65001 >nul
setlocal
set "INSTALLED=%LOCALAPPDATA%\DSTDailyGift\DST-DailyGift.ps1"

if exist "%INSTALLED%" (
    set "SCRIPT=%INSTALLED%"
) else (
    set "SCRIPT=%~dp0DST-DailyGift.ps1"
)

echo 正在运行 DST 每日登录礼物测试...
echo 如果今天已经成功运行过，本次使用 -Force 仍会重新测试。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Force -MaxAttempts 1 -RetryDelayMinutes 1
set "RC=%ERRORLEVEL%"
echo.
echo 脚本退出码：%RC%
pause
exit /b %RC%
