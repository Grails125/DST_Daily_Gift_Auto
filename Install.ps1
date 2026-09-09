[CmdletBinding()]
param(
    [string]$Time = '02:30'
)

$ErrorActionPreference = 'Stop'
$TaskName = 'DST Daily Login Gift'
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:LOCALAPPDATA 'DSTDailyGift'
$MainScript = Join-Path $SourceDir 'DST-DailyGift.ps1'

if (-not (Test-Path -LiteralPath $MainScript)) {
    throw ('Main script not found: ' + $MainScript)
}

if ($Time -notmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$') {
    throw ('Invalid time: ' + $Time + '. Use HH:mm, for example 02:30 or 21:30.')
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$InstalledScript = Join-Path $InstallDir 'DST-DailyGift.ps1'
Copy-Item -LiteralPath $MainScript -Destination $InstalledScript -Force
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'logs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'state') | Out-Null

$At = [datetime]::ParseExact($Time, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
$ArgumentLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $InstalledScript + '"'
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $ArgumentLine
$Trigger = New-ScheduledTaskTrigger -Daily -At $At
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 3)
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Automatically launch Don't Starve Together once per day, wait for Klei online login, then close only the DST process started by this task." -Force | Out-Null

Write-Host ''
Write-Host 'Installation completed.' -ForegroundColor Green
Write-Host ('Task name: ' + $TaskName)
Write-Host ('Daily time: ' + $Time)
Write-Host ('Install directory: ' + $InstallDir)
Write-Host ('Log directory: ' + (Join-Path $InstallDir 'logs'))
Write-Host ''
Write-Host 'Steam must already be signed in and Windows must have an interactive user session.'
Write-Host 'Run Run-Now.cmd to test immediately.'
