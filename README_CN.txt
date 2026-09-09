DST 每日登录礼物自动领取（Windows + Steam）
================================================

用途
----
每天自动启动《饥荒联机版》→ 等待客户端成功登录 Klei → 直接向 DST 窗口后台投递一次 Space → 打开主菜单礼物 → 等待动画/库存同步 → 只关闭本脚本自己启动的 DST。

特点
----
1. 不使用鼠标坐标、图像识别、AppActivate 或 SendKeys；通过 Win32 PostMessage 直接向 DST 主窗口后台发送 Space 的 WM_KEYDOWN/WM_KEYUP。
2. 如果检测到你已经在玩 DST：直接跳过，不接管、不关闭。
3. 根据 DST 的 client_log.txt 检查 Klei 在线登录成功信号；确认后才会发送空格键。
4. 默认失败最多尝试 3 次，每次间隔 30 分钟。
5. 当天成功后写入 success-YYYY-MM-DD.txt，避免任务重复启动。
6. Windows 从睡眠恢复后可“尽快运行错过的任务”；同时请求允许唤醒计算机运行任务。
7. 每次执行都写日志。

安装
----
1. 解压整个文件夹。
2. 双击 Install.cmd。
3. 输入每天运行时间；直接回车使用默认时间：02:30。
4. 安装后建议双击 Run-Now.cmd 测试一次。

默认计划时间
------------
02:30（安装时直接回车即可使用；也可以自行输入其他 HH:mm 时间）

稳定安装位置
------------
安装器会把主脚本复制到：
%LOCALAPPDATA%\DSTDailyGift\DST-DailyGift.ps1

所以安装完成后，即使移动下载/解压目录，计划任务也不会失效。

日志
----
%LOCALAPPDATA%\DSTDailyGift\logs\DST-DailyGift-YYYY-MM-DD.log

成功标记
--------
%LOCALAPPDATA%\DSTDailyGift\state\success-YYYY-MM-DD.txt

DST 官方客户端日志
-----------------
%USERPROFILE%\Documents\Klei\DoNotStarveTogether\client_log.txt
实际脚本使用 Windows 的“文档”系统路径，因此文档库被重定向时也能适配。

运行条件
--------
- Steam 已安装。
- Steam 已登录账号，并建议勾选记住登录状态。
- Windows 用户必须处于已登录状态；计划任务仍使用 Interactive 模式来启动 Steam/DST。后台 Space 本身不依赖前台焦点，也不会把按键发送到你正在操作的其他窗口。
- 电脑关机时无法运行。睡眠状态下是否能自动唤醒，还取决于 Windows 电源计划中的“允许使用唤醒定时器”。
- 如果 Steam 正在更新 DST，脚本最长等待 10 分钟看到游戏进程。

如何判断成功
------------
脚本等待 client_log.txt 中出现以下在线登录信号之一：
[200] Account Communication Success (3)
Logging in as KU_...

检测到后默认等待 15 秒让主菜单稳定，随后取得 DST 主窗口句柄并直接向该窗口后台投递一次 Space 的 WM_KEYDOWN/WM_KEYUP；不会调用 AppActivate，也不会切换前台焦点。发送成功后再等待 20 秒，让礼物开启动画和库存同步完成，然后关闭本次由脚本启动的游戏。

注意：脚本能确认“DST 已成功在线登录 Klei”以及“Space 的窗口消息已成功投递到 DST 主窗口”。PostMessage 返回成功表示消息进入窗口消息队列，不等同于 Klei 提供了“礼物已领取”的专用确认接口。Klei 没有提供给本地脚本一个稳定的“今天每日礼物已领取”专用返回值，因此脚本不会伪装成能够从日志 100% 验证具体礼物条目。

手动测试
--------
双击 Run-Now.cmd。
它会用 -Force 忽略“今天已经成功”的标记，并只尝试一次，方便测试。

卸载
----
双击 Uninstall.cmd。
可以选择先把日志备份到桌面，再删除计划任务和安装目录。

高级参数（可选）
----------------
DST-DailyGift.ps1 支持：
-Force
-MaxAttempts 3
-RetryDelayMinutes 30
-StartupTimeoutSeconds 600
-LoginTimeoutSeconds 360
-MainMenuSettleSeconds 15
-WindowMessageTimeoutSeconds 60
-RewardOpenWaitSeconds 20

例如：
powershell.exe -ExecutionPolicy Bypass -File DST-DailyGift.ps1 -Force -MaxAttempts 1


兼容性说明：PowerShell 脚本已使用 UTF-8 BOM 保存，兼容 Windows PowerShell 5.1 的中文环境。


后台按键说明
------------
此版本不依赖 DST 获得前台焦点。即使焦点在浏览器或其他软件上，脚本也不会向当前前台程序发送 Space。
需要注意：如果未来 DST 改为只接受 Raw Input/DirectInput 而忽略普通窗口键盘消息，后台 PostMessage 方案可能失效；届时日志会显示“消息已投递”，但游戏界面可能没有响应，需要更换输入方式。
