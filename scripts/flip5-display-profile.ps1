param(
    [int]$IntervalSec = 3,
    [switch]$Once,
    [switch]$DryRun
)

$Adb = if ($env:ADB_PATH) { $env:ADB_PATH } else { 'D:\Android\Sdk\platform-tools\adb.exe' }  # 可用环境变量 ADB_PATH 覆盖
$Log = Join-Path $PSScriptRoot 'flip5-profile.log'

# 档位定义
$TvBrightness   = 1   # 接外置屏：内屏手动压到最暗（省电，且镜像不能熄屏）
$PhoneBrightMode = 1  # 拔出后：1 = 自动亮度；0 = 手动
$Strategy = 'S2'      # 用户定案 2026-10-29：横M 竖M = 显示器永远 1:1
$Density  = 320       # 负载配置：sw800dp + xlrg 双保险过平板阈值（优酷等）；勿 reset 回 480
$ModeKey  = 'flip5_orient_mode'   # Settings.Secure，存 user_rotation 0-3

function Log($m) {
    $line = "$(Get-Date -Format 'MM-dd HH:mm:ss')  $m"
    Add-Content -Path $Log -Value $line -Encoding UTF8
    Write-Host $line
}

function Transport {
    $out = (& $Adb devices -l 2>&1 | Out-String) -split "`n"
    foreach ($l in $out) {
        if ($l -match 'model:SM_F7310' -and $l -match 'transport_id:(\d+)') { return [int]$Matches[1] }
    }
    return $null
}

function Sh([int]$t, [string]$cmd) {
    if ($DryRun) { Log "DRY  adb -t $t shell $cmd"; return '' }
    return ((& $Adb -t $t shell $cmd 2>&1 | Out-String) -join "`n").Trim()
}

# 只读命令不受 DryRun 影响，否则探针拿不到状态
function ShRead([int]$t, [string]$cmd) {
    return ((& $Adb -t $t shell $cmd 2>&1 | Out-String) -join "`n").Trim()
}

function ExternalState([int]$t) {
    $d = ShRead $t 'dumpsys display'
    $m = [regex]::Match($d, 'type=EXTERNAL, valid=true, isActive=true[^}]*?deviceWidth=(\d+), deviceHeight=(\d+)')
    if ($m.Success) {
        return [pscustomobject]@{ On = $true; W = [int]$m.Groups[1].Value; H = [int]$m.Groups[2].Value }
    }
    return [pscustomobject]@{ On = $false; W = 0; H = 0 }
}

function Orient-Now([int]$t) {
    $d = ShRead $t 'dumpsys display'
    $m = [regex]::Match($d, 'type=INTERNAL, valid=true, isActive=true[^}]*?orientation=(\d)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

# 外接镜像屏独立旋转对照表：手机方向 r -> 外接扫描旋转 e（显示器竖置，EDID 仍报横屏）
$ExtRot = @(3, 2, 1, 0)

function Sync-ExtRot([int]$t, [int]$o) {
    $d = ShRead $t 'dumpsys display'
    $m = [regex]::Match($d, 'type=EXTERNAL, valid=true, isActive=true, displayId=(\d+)')
    if (-not $m.Success) { return }
    $id = [int]$m.Groups[1].Value
    $want = $ExtRot[$o]
    $curLine = ShRead $t "cmd window user-rotation -d $id"
    $cur = ([regex]::Match($curLine, 'lock (\d)')).Groups[1].Value
    if ($cur -ne "$want") {
        Log "外接旋转 o=$o : $(if($cur){$cur}else{'free'}) -> $want"
        Sh $t "cmd window user-rotation -d $id lock $want" | Out-Null
    }
}

function Monitor-Override([int]$w, [int]$h) {
    if ($w -gt $h) { return "${h}x${w}" } else { return "${w}x${h}" }
}

function Override-For([int]$o, $ext) {
    switch ($Strategy) {
        'S1' { return 'reset' }
        'S2' { if ($ext.On) { return Monitor-Override $ext.W $ext.H } else { return 'reset' } }
        'S3' {
            if ($o -eq 1 -or $o -eq 3) { if ($ext.On) { return Monitor-Override $ext.W $ext.H } else { return 'reset' } }
            else { return 'reset' }
        }
    }
}

function Apply-Canvas([int]$t, [string]$want) {
    $cur = ((ShRead $t 'wm size') | Select-String 'Override size: (\S+)').Matches.Groups[1].Value
    if ($want -eq 'reset') {
        if ($cur) { Log "画布 $cur -> reset"; Sh $t 'wm size reset' | Out-Null }
    }
    elseif ($cur -ne $want) {
        Log "画布 $(if($cur){$cur}else{'none'}) -> $want"; Sh $t "wm size $want" | Out-Null
    }
}

function Apply-Connected([int]$t, [int]$w, [int]$h) {
    Log "接入 ${w}x${h}"
    Sh $t 'cmd window set-ignore-orientation-request true'     | Out-Null
    Sh $t 'settings put system screen_brightness_mode 0'       | Out-Null
    Sh $t "settings put system screen_brightness $TvBrightness" | Out-Null
}

function Apply-Disconnected([int]$t) {
    Log '拔出 -> 还原内屏（默认分辨率 / 自动亮度；旋转交给磁贴）'
    Sh $t 'cmd window set-ignore-orientation-request reset' | Out-Null
    Sh $t "settings put system screen_brightness_mode $PhoneBrightMode" | Out-Null
}

function Mode-Now([int]$t) {
    $a = ShRead $t 'settings get system accelerometer_rotation'
    if ($a -eq '1') { return -1 }
    return [int](ShRead $t 'settings get system user_rotation')
}

function Restore-Mode([int]$t) {
    $s = ShRead $t "settings get secure $ModeKey"
    if ($s -match '^[0-3]$') {
        Sh $t 'settings put system accelerometer_rotation 0' | Out-Null
        $u = ShRead $t 'settings get system user_rotation'
        if ($u -ne $s) { Log "恢复方向 -> $s"; Sh $t "settings put system user_rotation $s" | Out-Null }
    }
}

function Ensure-Invariants([int]$t, $ext, [int]$o) {
    # 传感器永远关（用户明确要求：碰手机不要乱转）
    $a = ShRead $t 'settings get system accelerometer_rotation'
    if ($a -ne '0') { Sh $t 'settings put system accelerometer_rotation 0' | Out-Null }
    $ign = ShRead $t 'cmd window get-ignore-orientation-request'
    if ($ext.On) {
        Sync-ExtRot $t $o
        if ($ign -notmatch 'true') { Log '自愈: ignore-orientation 丢失 -> 重设'; Sh $t 'cmd window set-ignore-orientation-request true' | Out-Null }
        $bm = ShRead $t 'settings get system screen_brightness_mode'
        if ($bm -ne '0') { Log "自愈: 亮度模式 $bm -> 0"; Sh $t 'settings put system screen_brightness_mode 0' | Out-Null; Sh $t "settings put system screen_brightness $TvBrightness" | Out-Null }
    }
    elseif ($ign -match 'true') {
        Log '自愈: 无外接但 ignore-orientation 仍开 -> 清掉'
        Sh $t 'cmd window set-ignore-orientation-request reset' | Out-Null
    }
    Apply-Canvas $t (Override-For $o $ext)
    $d = ((ShRead $t 'wm density') | Select-String 'Override density: (\d+)').Matches.Groups[1].Value
    if ($d -ne "$Density") { Log "自愈: 密度 $(if($d){$d}else{'none'}) -> $Density"; Sh $t "wm density $Density" | Out-Null }
    # 交叉守护：手机端 watcher 若被杀（拦截类程序/清理类 App），由 PC 端拉起
    $alive = ShRead $t "pgrep -f 'phone-watche[r]' | wc -l"
    if ($alive -match '^\s*0\s*$') {
        Log '自愈: 手机端 watcher 不在 -> 拉起'
        Sh $t 'setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &' | Out-Null
    }
}

# 单实例：开机任务与手动启动可能撞车
$Mutex = New-Object System.Threading.Mutex($false, 'flip5-display-profile')
if (-not $Mutex.WaitOne(0)) { Write-Host '已有实例在运行，本实例退出'; exit 0 }

Log "=== 启动 (pid=$PID strategy=$Strategy interval=${IntervalSec}s dryrun=$DryRun once=$Once) ==="
$last = $null
$lastMode = $null
$tick = 0
while ($true) {
    $t = Transport
    if (-not $t) {
        if ($last -ne 'offline') { Log '设备离线（无线调试未连/手机重启）'; $last = 'offline' }
        $script:lastMode = $null
    }
    else {
        if ($script:lastMode -eq $null) { Restore-Mode $t; $script:lastMode = Mode-Now $t }
        $e = ExternalState $t
        $o = Orient-Now $t
        $key = "o=$o on=$($e.On) $($e.W)x$($e.H) t$t"
        if ($key -ne $last) {
            if ($e.On) { Apply-Connected $t $e.W $e.H } else { Apply-Disconnected $t }
            $last = $key
        }
        $tick++
        if ($tick % 4 -eq 0) {
            Ensure-Invariants $t $e $o
            $m = Mode-Now $t
            if ($m -ne $script:lastMode) {
                if ($m -ge 0) { Log "方向变化 $($script:lastMode) -> $m（磁贴）-> 记录"; Sh $t "settings put secure $ModeKey $m" | Out-Null }
                $script:lastMode = $m
            }
        }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSec
}
