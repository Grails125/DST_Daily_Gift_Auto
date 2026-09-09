[CmdletBinding()]
param(
    [switch]$Force,
    [int]$MaxAttempts = 3,
    [int]$RetryDelayMinutes = 30,
    [int]$StartupTimeoutSeconds = 600,
    [int]$LoginTimeoutSeconds = 360,
    [int]$MainMenuSettleSeconds = 15,
    [int]$WindowMessageTimeoutSeconds = 60,
    [int]$RewardOpenWaitSeconds = 20
)

$ErrorActionPreference = 'Stop'
$AppId = 322330
$ProcessNames = @('dontstarve_steam_x64', 'dontstarve_steam')
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptRoot 'logs'
$StateDir = Join-Path $ScriptRoot 'state'
$Today = Get-Date -Format 'yyyy-MM-dd'
$RunLog = Join-Path $LogDir ("DST-DailyGift-{0}.log" -f $Today)
$SuccessMarker = Join-Path $StateDir ("success-{0}.txt" -f $Today)
$Documents = [Environment]::GetFolderPath('MyDocuments')
$ClientLog = Join-Path $Documents 'Klei\DoNotStarveTogether\client_log.txt'

New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

function Write-RunLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $RunLog -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-DSTProcesses {
    $result = @()
    foreach ($name in $ProcessNames) {
        $result += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
    return @($result | Sort-Object Id -Unique)
}

function Test-KleiHealth {
    try {
        $r = Invoke-WebRequest -Uri 'https://login.kleientertainment.com/HealthCheck' -UseBasicParsing -TimeoutSec 15
        $body = [string]$r.Content
        if ($r.StatusCode -eq 200 -and $body -match '(?i)OK') {
            Write-RunLog 'Klei HealthCheck 正常。' 'OK'
            return $true
        }
        Write-RunLog ("Klei HealthCheck 返回异常：HTTP {0}，内容：{1}" -f $r.StatusCode, ($body.Trim() -replace '\s+', ' ')) 'WARN'
        return $false
    }
    catch {
        Write-RunLog ("Klei HealthCheck 无法访问：{0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Start-DST {
    Write-RunLog "通过 Steam URI 启动 Don't Starve Together (AppID $AppId)..."
    try {
        Start-Process ("steam://rungameid/{0}" -f $AppId) | Out-Null
        return $true
    }
    catch {
        Write-RunLog ("Steam URI 启动失败：{0}" -f $_.Exception.Message) 'WARN'
    }

    # URI 未注册时，尝试从注册表定位 Steam.exe。
    $steamExe = $null
    foreach ($regPath in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $p = Get-ItemProperty -Path $regPath -ErrorAction Stop
            if ($p.SteamExe -and (Test-Path $p.SteamExe)) { $steamExe = $p.SteamExe; break }
            if ($p.InstallPath) {
                $candidate = Join-Path $p.InstallPath 'steam.exe'
                if (Test-Path $candidate) { $steamExe = $candidate; break }
            }
        } catch { }
    }

    if ($steamExe) {
        try {
            Write-RunLog "改用 Steam.exe -applaunch $AppId 启动。"
            Start-Process -FilePath $steamExe -ArgumentList '-applaunch', $AppId | Out-Null
            return $true
        }
        catch {
            Write-RunLog ("Steam.exe 启动失败：{0}" -f $_.Exception.Message) 'ERROR'
        }
    }

    return $false
}

function Wait-DSTProcess {
    param([datetime]$NotBefore, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $procs = Get-DSTProcesses
        foreach ($p in $procs) {
            try {
                if ($p.StartTime -ge $NotBefore.AddSeconds(-10)) {
                    Write-RunLog ("检测到 DST 进程：{0}.exe (PID {1})" -f $p.ProcessName, $p.Id) 'OK'
                    return $p
                }
            } catch { }
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Get-ClientLogTail {
    param([int]$Lines = 800)
    if (-not (Test-Path -LiteralPath $ClientLog)) { return '' }
    try {
        return ((Get-Content -LiteralPath $ClientLog -Tail $Lines -ErrorAction Stop) -join "`n")
    }
    catch {
        return ''
    }
}

function Wait-KleiLogin {
    param([datetime]$LaunchTime, [int]$TimeoutSeconds, [int]$ProcessId)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $sawFreshLog = $false

    do {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            Write-RunLog 'DST 在等待登录期间提前退出。' 'ERROR'
            return $false
        }

        if (Test-Path -LiteralPath $ClientLog) {
            try {
                $item = Get-Item -LiteralPath $ClientLog -ErrorAction Stop
                if ($item.LastWriteTime -ge $LaunchTime.AddSeconds(-5)) {
                    $sawFreshLog = $true
                    $tail = Get-ClientLogTail

                    # 只分析最后一次 Starting Up 之后的当前会话，避免旧日志里的成功标志造成误判。
                    $sessionTail = $tail
                    $sessionStart = $tail.LastIndexOf('Starting Up')
                    if ($sessionStart -ge 0) {
                        $sessionTail = $tail.Substring($sessionStart)
                    }

                    # 主菜单在线登录成功时，常见日志信号如下。
                    if ($sessionTail -match '\[200\]\s+Account Communication Success \(3\)' -or
                        $sessionTail -match 'Logging in as KU_[A-Za-z0-9_-]+') {
                        Write-RunLog '检测到 Klei 账号在线登录成功日志。' 'OK'
                        return $true
                    }
                }
            } catch { }
        }

        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    if (-not $sawFreshLog) {
        Write-RunLog ("等待超时：未检测到本次启动产生的新 client_log.txt。路径：{0}" -f $ClientLog) 'ERROR'
    } else {
        $tail = Get-ClientLogTail -Lines 250
        $hint = @()
        if ($tail -match '(?i)CURL ERROR') { $hint += '检测到 CURL ERROR' }
        if ($tail -match '(?i)Account Failed') { $hint += '检测到 Account Failed' }
        if ($tail -match '(?i)Could not resolve host') { $hint += '检测到 DNS 解析失败' }
        if ($hint.Count -gt 0) {
            Write-RunLog ("等待 Klei 登录成功超时；" + ($hint -join '；') + '。') 'ERROR'
        } else {
            Write-RunLog '等待 Klei 登录成功日志超时。' 'ERROR'
        }
    }
    return $false
}


function Initialize-BackgroundInputApi {
    if ('DSTBackgroundInput.NativeMethods' -as [type]) { return $true }

    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DSTBackgroundInput
{
    public static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PostMessage(IntPtr hWnd, UInt32 Msg, UIntPtr wParam, UIntPtr lParam);

        [DllImport("user32.dll")]
        public static extern UInt32 MapVirtualKey(UInt32 uCode, UInt32 uMapType);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindow(IntPtr hWnd);
    }
}
"@ -ErrorAction Stop
        return $true
    }
    catch {
        Write-RunLog ("加载 Win32 后台按键 API 失败：{0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Send-DSTSpaceKey {
    param([int]$ProcessId, [int]$TimeoutSeconds = 60)

    if (-not (Initialize-BackgroundInputApi)) { return $false }

    $WM_KEYDOWN = [uint32]0x0100
    $WM_KEYUP   = [uint32]0x0101
    $VK_SPACE   = [uint32]0x20
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $p) {
            Write-RunLog 'DST 在等待主窗口句柄期间已经退出。' 'ERROR'
            return $false
        }

        try {
            $p.Refresh()
            $hWnd = [IntPtr]$p.MainWindowHandle
            if ($hWnd -ne [IntPtr]::Zero -and [DSTBackgroundInput.NativeMethods]::IsWindow($hWnd)) {
                # WM_KEYDOWN/WM_KEYUP 的 lParam：repeat=1，附带实际扫描码；KEYUP 再设置 previous/transition 位。
                $scanCode = [uint32][DSTBackgroundInput.NativeMethods]::MapVirtualKey($VK_SPACE, 0)
                $downValue = [uint64]1 + ([uint64]$scanCode * 65536)
                $upValue = $downValue + [uint64]3221225472  # 0xC0000000

                $downOk = [DSTBackgroundInput.NativeMethods]::PostMessage(
                    $hWnd,
                    $WM_KEYDOWN,
                    [UIntPtr]([uint64]$VK_SPACE),
                    [UIntPtr]$downValue
                )

                if (-not $downOk) {
                    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Write-RunLog ("向 DST 后台投递 WM_KEYDOWN 失败，Win32Error={0}。" -f $err) 'WARN'
                    Start-Sleep -Seconds 2
                    continue
                }

                Start-Sleep -Milliseconds 120

                $upOk = [DSTBackgroundInput.NativeMethods]::PostMessage(
                    $hWnd,
                    $WM_KEYUP,
                    [UIntPtr]([uint64]$VK_SPACE),
                    [UIntPtr]$upValue
                )

                if (-not $upOk) {
                    # KEYDOWN 已成功入队时，额外再尝试一次 KEYUP，避免按键状态卡住。
                    Start-Sleep -Milliseconds 100
                    $upOk = [DSTBackgroundInput.NativeMethods]::PostMessage(
                        $hWnd,
                        $WM_KEYUP,
                        [UIntPtr]([uint64]$VK_SPACE),
                        [UIntPtr]$upValue
                    )
                }

                if ($upOk) {
                    Write-RunLog ("已向 DST 主窗口后台投递一次 Space (PID {0}, HWND 0x{1:X})；未切换前台焦点。" -f $ProcessId, $hWnd.ToInt64()) 'OK'
                    return $true
                }

                $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-RunLog ("WM_KEYDOWN 已投递，但 WM_KEYUP 投递失败，Win32Error={0}。" -f $err) 'ERROR'
                return $false
            }
        }
        catch {
            Write-RunLog ("尝试向 DST 后台窗口发送 Space 时出现异常：{0}" -f $_.Exception.Message) 'WARN'
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    Write-RunLog ("等待 {0} 秒仍未获得有效 DST 主窗口句柄，未发送后台 Space。" -f $TimeoutSeconds) 'ERROR'
    return $false
}

function Stop-OurDST {
    param([int]$ProcessId)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return }

    Write-RunLog ("准备关闭本脚本启动的 DST (PID {0})..." -f $ProcessId)
    try {
        if ($p.MainWindowHandle -ne 0) {
            [void]$p.CloseMainWindow()
            if ($p.WaitForExit(15000)) {
                Write-RunLog 'DST 已正常退出。' 'OK'
                return
            }
        }
    } catch { }

    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($p) {
        Write-RunLog 'DST 未在 15 秒内正常退出，结束该自动化实例。' 'WARN'
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# 防止任务被重复启动。
$mutex = New-Object System.Threading.Mutex($false, 'Local\DSTDailyGiftAutomation')
$hasMutex = $false
try {
    try {
        $hasMutex = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $hasMutex = $true
    }
    if (-not $hasMutex) {
        Write-RunLog '已有一个自动领取实例正在运行，本次退出。' 'WARN'
        exit 0
    }

    Write-RunLog '========== DST 每日登录礼物自动领取开始 =========='

    if ((Test-Path -LiteralPath $SuccessMarker) -and -not $Force) {
        Write-RunLog '今天已经记录过一次成功登录，跳过重复启动。' 'OK'
        exit 0
    }

    $alreadyRunning = Get-DSTProcesses
    if ($alreadyRunning.Count -gt 0) {
        $ids = ($alreadyRunning | ForEach-Object { $_.Id }) -join ', '
        Write-RunLog ("检测到 DST 已经在运行 (PID: {0})。为避免影响正在玩的游戏，本次不接管、不关闭。" -f $ids) 'WARN'
        exit 0
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-RunLog ("第 {0}/{1} 次尝试。" -f $attempt, $MaxAttempts)
        [void](Test-KleiHealth)

        $launchTime = Get-Date
        if (-not (Start-DST)) {
            Write-RunLog '无法启动 Steam/DST。' 'ERROR'
            if ($attempt -lt $MaxAttempts) {
                Write-RunLog ("{0} 分钟后重试。" -f $RetryDelayMinutes) 'WARN'
                Start-Sleep -Seconds ($RetryDelayMinutes * 60)
                continue
            }
            exit 2
        }

        $proc = Wait-DSTProcess -NotBefore $launchTime -TimeoutSeconds $StartupTimeoutSeconds
        if (-not $proc) {
            Write-RunLog ("等待 DST 启动超过 {0} 秒。Steam 可能正在更新、未登录或启动失败。" -f $StartupTimeoutSeconds) 'ERROR'
            if ($attempt -lt $MaxAttempts) {
                Write-RunLog ("{0} 分钟后重试。" -f $RetryDelayMinutes) 'WARN'
                Start-Sleep -Seconds ($RetryDelayMinutes * 60)
                continue
            }
            exit 3
        }

        $loginOk = Wait-KleiLogin -LaunchTime $launchTime -TimeoutSeconds $LoginTimeoutSeconds -ProcessId $proc.Id
        if ($loginOk) {
            Write-RunLog ("在线登录已确认，等待 {0} 秒让主菜单稳定后自动打开礼物。" -f $MainMenuSettleSeconds)
            Start-Sleep -Seconds $MainMenuSettleSeconds

            $spaceSent = Send-DSTSpaceKey -ProcessId $proc.Id -TimeoutSeconds $WindowMessageTimeoutSeconds
            if ($spaceSent) {
                Write-RunLog ("空格键已发送，再等待 {0} 秒用于礼物开启动画/库存同步。" -f $RewardOpenWaitSeconds)
                Start-Sleep -Seconds $RewardOpenWaitSeconds

                # 只有脚本启动的这个 PID 才会被关闭。
                Stop-OurDST -ProcessId $proc.Id

                $markerText = "{0}`r`nKlei online login detected and one SPACE key was posted directly to the DST window in background.`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Set-Content -LiteralPath $SuccessMarker -Value $markerText -Encoding UTF8
                Write-RunLog '自动打开礼物流程完成，并写入今日成功标记。' 'OK'
                exit 0
            }

            Write-RunLog 'Klei 登录成功，但后台发送空格键失败；本次不记为成功。' 'ERROR'
        }

        # 本次是脚本启动的实例，失败后关闭再重试。
        Stop-OurDST -ProcessId $proc.Id

        if ($attempt -lt $MaxAttempts) {
            Write-RunLog ("本次自动领取未完成，{0} 分钟后重试。" -f $RetryDelayMinutes) 'WARN'
            Start-Sleep -Seconds ($RetryDelayMinutes * 60)
        }
    }

    Write-RunLog '所有尝试均失败。请查看本日日志与 DST client_log.txt。' 'ERROR'
    exit 4
}
finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch { }
    }
    if ($mutex) { $mutex.Dispose() }
}
