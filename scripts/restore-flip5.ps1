param(
    [switch]$DryRun,
    [switch]$SkipPackages
)

# Flip5 恢复出厂后的一键重建脚本。对照 state-snapshot.txt 使用。
$Adb  = if ($env:ADB_PATH) { $env:ADB_PATH } else { 'D:\Android\Sdk\platform-tools\adb.exe' }
$Work = if ($env:FLIP5_WORK) { $env:FLIP5_WORK } else { Split-Path $PSScriptRoot -Parent }  # 仓库根
$WantFirmware = @('F7310ZSU9HZIJ', 'F7310ZSS9GZI1')   # 37=OneUI9 / 36=OneUI8，都验证过可部署

# 需要装回的手机端 App（本地已有，无需联网）
$Apks = [ordered]@{
    'app.orchard.tv'      = "$Work\aerial-standard.apk"
    'org.smarttube.stable' = "$Work\apk\SmartTube_32.68_arm64.apk"
}

# 恢复出厂后这些预装会全部回来，按快照重新禁用
$Disabled = @(
    'com.facebook.system', 'com.facebook.services', 'com.facebook.appmanager',
    'com.google.android.apps.bard', 'com.google.android.apps.tachyon',
    'com.google.android.apps.carrier.carrierwifi', 'com.google.android.glasses.core',
    'com.google.android.gms.supervision', 'com.google.android.projection.gearhead',
    'com.hiya.star', 'com.microsoft.appmanager', 'com.microsoft.skydrive',
    'com.samsung.android.bixby.agent', 'com.samsung.android.bixby.wakeup',
    'com.samsung.android.knox.zt.framework'
)

# 注意：必须用 disable-user --user 0；裸 pm disable 会 SecurityException
$Settings = @(
    @('system', 'screen_brightness_mode', '0'),
    @('system', 'screen_brightness', '1'),
    @('system', 'show_taps', '1'),
    @('global', 'force_resizable_activities', '1')
)
# 注意：user_rotation / accelerometer_rotation 不在此列——旋转归方向磁贴 + watcher 的 secure 键管

function Log($m) { Write-Host $m }
function Transport {
    $out = (& $Adb devices -l 2>&1 | Out-String) -split "`n"
    foreach ($l in $out) {
        if ($l -match 'model:SM_F7310' -and $l -match 'transport_id:(\d+)') { return [int]$Matches[1] }
    }
    return $null
}
function Sh([string]$cmd) {
    if ($DryRun) { Log "DRY  $cmd"; return '' }
    # 2>&1 后强制转字符串，避免 adb 的 stderr 变成 PowerShell 错误记录污染输出
    return ((& $Adb -t $script:T shell $cmd 2>&1 | ForEach-Object { "$_" } | Out-String) -join "`n").Trim()
}
function ShRead([string]$cmd) {
    return ((& $Adb -t $script:T shell $cmd 2>&1 | ForEach-Object { "$_" } | Out-String) -join "`n").Trim()
}
function InstallApk([string]$path) {
    # 注意：adb install 不是 adb shell install（后者是 toybox 复制文件）
    if ($DryRun) { Log "DRY  adb -t $T install -r -g $path"; return 'dryrun' }
    return ((& $Adb -t $script:T install -r -g $path 2>&1 | Out-String) -join "`n").Trim()
}

Log '== 0 等待设备 =='
$T = $null
for ($i = 0; $i -lt 60; $i++) {
    $T = Transport
    if ($T) { break }
    Start-Sleep 2
}
if (-not $T) { Log '没连上 SM_F7310。手机侧：设置→开发者选项→无线调试→选这台电脑配对，然后 adb pair <ip>:<端口> <6位码>'; exit 1 }
$script:T = $T
Log "transport_id = $T"

Log '== 1 固件核对 =='
$fw = ShRead 'getprop ro.build.version.incremental'
if ($WantFirmware -contains $fw) { Log "固件一致：$fw" }
else { Log "警告：设备固件 $fw 不在白名单 ($($WantFirmware -join ' / '))，后续命令仍会执行，但请先确认是否被重刷" }

Log '== 2 装回 App =='
foreach ($pkg in $Apks.Keys) {
    $path = $Apks[$pkg]
    $has = ShRead "pm list packages $pkg"
    if ($has -match [regex]::Escape("package:$pkg")) { Log "$pkg 已存在，跳过"; continue }
    if (-not (Test-Path $path)) { Log "缺文件：$path（跳过）"; continue }
    $r = InstallApk $path
    Log "$pkg <- $(Split-Path $path -Leaf) : $(if ($r -match 'Success') { 'Success' } else { $r })"
}

Log '== 2b 方向磁贴（顺/逆时针） =='
$TilePkg = 'dev.zflip5.orienttile'
$TileApk = "$Work\orient-tile\dist\orient-tile.apk"
if ((ShRead "pm list packages $TilePkg") -notmatch "package:$TilePkg") {
    if (Test-Path $TileApk) { Log "$TilePkg <- orient-tile.apk : $(InstallApk $TileApk)" }
    else { Log "缺文件：$TileApk（先跑 orient-tile/build.sh）" }
}
Sh "cmd appops set $TilePkg WRITE_SETTINGS allow" | Out-Null
$cur = ShRead 'settings get secure sysui_qs_tiles'
$parts = @($cur -split ',' | Where-Object { $_ -and ($_ -notmatch 'orienttile') })
$parts += 'custom(dev.zflip5.orienttile/.RotateCwTileService)'
$parts += 'custom(dev.zflip5.orienttile/.RotateCcwTileService)'
Sh "cmd statusbar set-tiles '$($parts -join ',')'" | Out-Null
Start-Sleep 4   # SystemUI 落盘有延迟，立刻读会少算
Log ("磁贴列表含 orienttile 条目数 = " + (@(ShRead 'settings get secure sysui_qs_tiles' -split ',' | Where-Object { $_ -match 'orienttile' }).Count))

Log '== 3 默认桌面 = Aerial =='
Sh "cmd role add-role-holder --user 0 android.app.role.HOME app.orchard.tv" | Out-Null
Log ("HOME = " + (ShRead 'cmd role get-role-holders android.app.role.HOME'))

if (-not $SkipPackages) {
    Log '== 4 禁用预装 =='
    foreach ($p in $Disabled) {
        if (-not $p) { continue }   # 空元素会让 pm 收到空包名并抛 SecurityException
        $r = (Sh "pm disable-user --user 0 $p") -split "`n" | Where-Object { $_ -and ($_ -notmatch '^adb\.exe') } | Select-Object -First 1
        if (-not $r) { $r = 'throw/受保护包（当前固件 shell 禁不了；若已禁用则无影响）' }
        Log ("{0,-52} {1}" -f $p, $r)
    }
}

Log '== 5 settings =='
foreach ($s in $Settings) {
    Sh "settings put $($s[0]) $($s[1]) $($s[2])" | Out-Null
    Log ("{0,-46} = {1}" -f "$($s[0])/$($s[1])", (ShRead "settings get $($s[0]) $($s[1])"))
}
$m = ShRead 'settings get secure flip5_orient_mode'
if ($m -notmatch '^[0-3]$') {
    Sh 'settings put secure flip5_orient_mode 0' | Out-Null   # 竖置显示器下的默认方向 = 竖屏
    Log 'flip5_orient_mode 缺失 -> 置 0（竖屏）'
}

Log '== 6 显示档位（按外接屏是否存在） =='
$d = ShRead 'dumpsys display'
$m = [regex]::Match($d, 'type=EXTERNAL, valid=true, isActive=true[^}]*?deviceWidth=(\d+), deviceHeight=(\d+)')
if ($m.Success) {
    $w = [int]$m.Groups[1].Value; $h = [int]$m.Groups[2].Value
    $override = if ($w -gt $h) { "${h}x${w}" } else { "${w}x${h}" }
    Log "外接 ${w}x${h} -> wm size $override（画布=外接比例；显示器竖置时由 watcher 另设外接扫描旋转）"
    Sh "wm size $override" | Out-Null
    Sh 'cmd window user-rotation lock 1' | Out-Null
    Sh 'cmd window set-ignore-orientation-request true' | Out-Null
} else {
    Log '未接外置屏 -> 保持内屏默认'
    Sh 'wm size reset' | Out-Null
    Sh 'cmd window set-ignore-orientation-request reset' | Out-Null
}
Log ("wm size : " + ((ShRead 'wm size') -join ' / '))
# 密度是负载配置：320dpi → sw800dp ≥600dp 阈值，App 走平板布局分支（优酷等）；勿 reset 回 480
Sh 'wm density 320' | Out-Null
Log ("wm density: " + ((ShRead 'wm density') -join ' / '))

Log '== 6b 手机端 watcher =='
& $Adb -t $script:T push "$Work\scripts\phone-watcher.sh" /data/local/tmp/phone-watcher.sh 2>&1 | Out-Null
Sh "sed -i 's/\r$//' /data/local/tmp/phone-watcher.sh; pkill -f 'local/tmp/phone-watche[r]'" | Out-Null
Sh 'setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &' | Out-Null
Start-Sleep 2
Log ("手机端 watcher pid = " + (ShRead "pgrep -f 'phone-watche[r]' | head -1"))

Log '== 7 校验 =='
$checks = @(
    @('wm override',   'wm size',                  'Override size'),
    @('HOME',          'cmd role get-role-holders android.app.role.HOME', 'app.orchard.tv'),
    @('禁用数',        'pm list packages -d',      'package:'),
    @('Aerial',        'pm list packages app.orchard.tv', 'package:app.orchard.tv'),
    @('SmartTube',     'pm list packages org.smarttube',  'package:org.smarttube.stable')
)
foreach ($c in $checks) {
    $v = ShRead $c[1]
    $n = (@($v -split "`n" | Where-Object { $_ -like "*$($c[2])*" }).Count)
    Log ("{0,-12} 命中 {1}  ({2})" -f $c[0], $n, ($v -replace "`n", ' | '))
}
Log '完成。下一步：跑 register-autostart.ps1 重建开机任务，再跑 flip5-display-profile.ps1 常驻 watcher。'
