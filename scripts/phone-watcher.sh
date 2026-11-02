#!/system/bin/sh
# Flip5 手机端显示档位 watcher（shell 权限，无需电脑）
# 职责：外接屏插拔切亮度/ignore-orientation；按"方向+策略"切画布；旋转只做恢复与学习（事实源=磁贴）
# 日志：/data/local/tmp/flip5-profile-phone.log

LOG=/data/local/tmp/flip5-profile-phone.log
INTERVAL=2
STRATEGY=S2          # 用户定案 2026-10-29：横M 竖M = 显示器永远 1:1
DENSITY=320          # 负载配置：sw800dp+xlrg 双保险过平板阈值；勿 reset 回 480
MODE_KEY=flip5_orient_mode   # Settings.Secure，存 user_rotation 0-3
FIX_FILE=/sdcard/Android/data/dev.zflip5.orienttile/files/fix   # 磁贴写时间戳 = 请求全量重放；App 写自定义 Settings 键会被固件一律拒绝，只能走文件
BEAT_KEY=flip5_beat          # Settings.System，仅 shell 侧调试用（App 读不到自定义键，也读不到 shell 在它目录里建的文件）

log() { echo "$(date '+%m-%d %H:%M:%S')  $1" >> $LOG; }

# watchdog：外壳进程命令行不含 "worker"，被拦截/清理类程序杀掉 worker 时 2 秒内重启。
# 杀 worker：pkill -f 'phone-watcher.sh worker'；全杀：pkill -f 'phone-watche[r]'
if [ "$1" != "worker" ]; then
    log "=== watchdog 启动 pid=$$ ==="
    while :; do
        sh "$0" worker
        log "worker 退出 rc=$? ，2 秒后重启"
        sleep 2
    done
fi

ext_res() {
    dumpsys display 2>/dev/null | grep -o 'type=EXTERNAL, valid=true, isActive=true[^}]*' \
        | grep -o 'deviceWidth=[0-9]*, deviceHeight=[0-9]*' | head -1 \
        | sed 's/deviceWidth=\([0-9]*\), deviceHeight=\([0-9]*\)/\1 \2/'
}

orient_now() {
    # 方向一律取 user_rotation，不要读 viewport 的 orientation：
    # Flip5 有两块 type=INTERNAL 屏（外屏 FlexWindow installOrientation=1），合盖时按
    # "第一个 isActive 的 INTERNAL" 取会读到躺 90° 的外屏，把整机误判成横档（2026-11-02 实踩）。
    mode_now
}

# 外接镜像屏独立旋转对照表：手机方向 r -> 外接扫描旋转 e（显示器竖置，EDID 仍报横屏）
# 初值按旋转合成规律填；哪个方向看着不对改对应一项即可
EXT_ROT_0=3
EXT_ROT_1=2
EXT_ROT_2=1
EXT_ROT_3=0

ext_id() {
    dumpsys display 2>/dev/null | grep -o 'type=EXTERNAL, valid=true, isActive=true, displayId=[0-9]*' \
        | grep -o '[0-9]*$' | head -1
}

sync_ext_rot() {  # $1=手机方向 0-3
    id=$(ext_id)
    [ -z "$id" ] && return
    eval want=\$EXT_ROT_$1
    [ -z "$want" ] && return
    cur=$(cmd window user-rotation -d "$id" 2>/dev/null | grep -oE 'lock [0-9]' | awk '{print $2}')
    if [ "$cur" != "$want" ]; then
        log "外接旋转 o=$1: ${cur:-free} -> $want"
        cmd window user-rotation -d "$id" lock "$want"
    fi
}

mon_ov() {  # 外接 W H -> 竖屏形状 override（横屏下系统换成 WxH，与外接 1:1）
    w=$1; h=$2
    if [ "$w" -gt "$h" ]; then echo "${h}x${w}"; else echo "${w}x${h}"; fi
}

override_for() {  # $1=orientation $2="W H"|空
    case "$STRATEGY" in
        S1) echo reset ;;
        S2) if [ -n "$2" ]; then mon_ov $2; else echo reset; fi ;;
        S3) case "$1" in
                1|3) if [ -n "$2" ]; then mon_ov $2; else echo reset; fi ;;
                *)   echo reset ;;
            esac ;;
    esac
}

apply_canvas() {  # $1=desired(reset|WxH)
    cur=$(wm size | grep Override | awk '{print $3}')
    if [ "$1" = "reset" ]; then
        [ -n "$cur" ] && { log "画布 $cur -> reset"; wm size reset; }
    elif [ "$cur" != "$1" ]; then
        log "画布 ${cur:-none} -> $1"; wm size $1
    fi
}

apply_on()  { log "接入 $1x$2"; cmd window set-ignore-orientation-request true; settings put system screen_brightness_mode 0; settings put system screen_brightness 1; }
apply_off() { log "拔出 -> 还原内屏"; cmd window set-ignore-orientation-request reset; settings put system screen_brightness_mode 1; }

mode_now() {  # accel 恒 0 前提下 = user_rotation；accel=1 视为"自动"返回 -1
    a=$(settings get system accelerometer_rotation)
    [ "$a" = "1" ] && { echo -1; return; }
    settings get system user_rotation
}

restore_mode() {
    m=$(settings get secure $MODE_KEY)
    case "$m" in 0|1|2|3)
        settings put system accelerometer_rotation 0
        if [ "$(settings get system user_rotation)" != "$m" ]; then
            log "开机恢复方向 -> $m"; settings put system user_rotation "$m"
        fi ;;
    esac
}

learn_mode() {
    cur=$(mode_now)
    if [ "$cur" != "$last_mode" ]; then
        if [ "$cur" != "-1" ]; then
            log "方向变化 $last_mode -> $cur（磁贴）-> 记录"
            settings put secure $MODE_KEY "$cur"
        fi
        last_mode=$cur
    fi
}

ensure() {  # 每轮核对不变量（幂等）
    o=$(orient_now); res=$(ext_res)
    # 传感器永远关（用户明确要求：碰手机不要乱转）
    [ "$(settings get system accelerometer_rotation)" = "0" ] || settings put system accelerometer_rotation 0
    if [ -n "$res" ]; then
        sync_ext_rot "$o"
        cmd window get-ignore-orientation-request 2>/dev/null | grep -q true \
            || { log "自愈: ignore-orientation 丢失 -> 重设"; cmd window set-ignore-orientation-request true; }
        bm=$(settings get system screen_brightness_mode)
        [ "$bm" = "0" ] || { log "自愈: 亮度模式 $bm -> 0"; settings put system screen_brightness_mode 0; settings put system screen_brightness 1; }
    else
        cmd window get-ignore-orientation-request 2>/dev/null | grep -q true \
            && { log "自愈: 无外接但 ignore 仍开 -> 清掉"; cmd window set-ignore-orientation-request reset; }
    fi
    apply_canvas "$(override_for "$o" "$res")"
    # 密度自愈：320dpi 是平板分支的前提（sw800dp），被 reset 会导致优酷等回手机布局
    cur_d=$(wm density | grep Override | awk '{print $3}')
    [ "$cur_d" = "$DENSITY" ] || { log "自愈: 密度 ${cur_d:-none} -> $DENSITY"; wm density $DENSITY; }
}

repair() {  # 磁贴触发：不看差量，无条件重放整套（"看着对但没生效"时 wm size 重写本身就是那一下抖动）
    res=$(ext_res); o=$(mode_now)
    case "$o" in 0|1|2|3) settings put system accelerometer_rotation 0 ;; esac
    restore_mode; o=$(mode_now)
    if [ -n "$res" ]; then
        apply_on ${res% *} ${res#* }
        id=$(ext_id)
        if [ -n "$id" ]; then
            eval want=\$EXT_ROT_$o
            [ -n "$want" ] && { log "强制外接旋转 d$id -> $want"; cmd window user-rotation -d "$id" lock "$want"; }
        fi
    else
        apply_off
    fi
    want_c=$(override_for "$o" "$res")
    if [ "$want_c" = "reset" ]; then log "强制画布 reset"; wm size reset
    else log "强制画布 -> $want_c"; wm size "$want_c"; fi
    log "强制密度 -> $DENSITY"; wm density $DENSITY
    last=""; last_u=$(settings get system user_rotation); last_mode=$(mode_now)
}

log "=== 手机端 watcher 启动 pid=$$ strategy=$STRATEGY interval=${INTERVAL}s ==="
restore_mode
last_mode=$(mode_now)
last_u=$(settings get system user_rotation)
last=""
tick=0
last_fix=""   # 故意置空：启动即把残留的触发文件当新请求消费掉（顺带等于开机全量重放一次）
beat=0
while :; do
    # 心跳：每约 6 秒写一次，磁贴读它判断守护是否还活着
    tick=$((tick + 1))
    if [ $((tick % 3)) -eq 0 ] || [ "$beat" = "0" ]; then
        beat=$(date +%s); settings put system $BEAT_KEY "$beat"   # 仅 shell 侧调试；App 读不到自定义 Settings 键
    fi
    # 磁贴"修复画面"触发：文件内容变了就无条件重放整套
    fx=$(cat $FIX_FILE 2>/dev/null)
    if [ -n "$fx" ] && [ "$fx" != "$last_fix" ]; then
        last_fix=$fx
        log "--- 收到修复触发 ---"
        repair
        rm -f $FIX_FILE   # 消费掉：磁贴靠"文件还在不在"判断守护有没有干活
    fi
    # 快路径（每轮，便宜）：方向一变立刻同步外接旋转，避免"转完等几秒才满屏"
    u=$(settings get system user_rotation)
    if [ "$u" != "$last_u" ]; then
        last_u=$u
        if [ -n "$(ext_res)" ]; then
            sync_ext_rot "$u"
            log "方向 -> $u，外接旋转已同步"
        fi
    fi
    if [ $((tick % 3)) -eq 0 ]; then
        o=$(orient_now); res=$(ext_res)
        key="o=$o ext=$res"
        if [ "$key" != "$last" ]; then
            if [ -n "$res" ]; then apply_on ${res% *} ${res#* }; else apply_off; fi
            last=$key
        fi
        ensure
        learn_mode
    fi
    sleep $INTERVAL
done
