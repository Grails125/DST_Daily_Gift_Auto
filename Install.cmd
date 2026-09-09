@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ==========================================
echo  DST 每日登录礼物 - 一键安装
echo ==========================================
echo.
set "TASKTIME=02:30"
set /p "TASKTIME=请输入每天运行时间 HH:mm [默认 02:30]: "
if "%TASKTIME%"=="" set "TASKTIME=02:30"
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Time "%TASKTIME%"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo 安装失败，错误码：%RC%
) else (
    echo 安装成功。建议现在双击 Run-Now.cmd 测试一次。
)
echo.
pause
exit /b %RC%
