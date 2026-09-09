[CmdletBinding()]
param([switch]$KeepLogs)

$TaskName = 'DST Daily Login Gift'
$InstallDir = Join-Path $env:LOCALAPPDATA 'DSTDailyGift'

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "已删除计划任务：$TaskName" -ForegroundColor Green
}
catch {
    Write-Host '计划任务不存在或无法删除，可忽略。' -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $InstallDir) {
    if ($KeepLogs) {
        $backup = Join-Path $env:USERPROFILE ("Desktop\DSTDailyGift-logs-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $logs = Join-Path $InstallDir 'logs'
        if (Test-Path $logs) {
            Copy-Item -Path $logs -Destination $backup -Recurse -Force
            Write-Host "日志已备份到：$backup"
        }
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "已删除安装目录：$InstallDir" -ForegroundColor Green
}
