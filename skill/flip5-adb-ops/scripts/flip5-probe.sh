#!/usr/bin/env bash
# Flip5 invariant probe - ASCII-safe output, auto-detects transport.
# usage: flip5-probe.sh [adb-path]
ADB="${1:-/d/Android/Sdk/platform-tools/adb.exe}"
export MSYS2_ARG_CONV_EXCL="*"
T=$("$ADB" devices -l 2>/dev/null | grep -o 'transport_id:[0-9]*' | cut -d: -f2 | tail -1)
if [ -z "$T" ]; then echo "NO_DEVICE (screen asleep? not paired?)"; exit 1; fi
sh() { "$ADB" -t "$T" shell "$1" 2>&1 | tr -d '\r'; }
echo "transport=$T"
echo "firmware=$(sh 'getprop ro.build.version.incremental') region=$(sh 'getprop ro.oem.key1') warranty=$(sh 'getprop ro.boot.warranty_bit')"
echo "canvas=$(sh 'wm size' | tail -1)"
echo "user_rotation=$(sh 'settings get system user_rotation') accel=$(sh 'settings get system accelerometer_rotation') mode_key=$(sh 'settings get secure flip5_orient_mode')"
echo "ignore_orient=$(sh 'cmd window get-ignore-orientation-request' | head -1)"
echo "brightness_mode=$(sh 'settings get system screen_brightness_mode') brightness=$(sh 'settings get system screen_brightness')"
echo "home=$(sh 'cmd role get-role-holders android.app.role.HOME')"
echo "disabled_count=$(sh 'pm list packages -d | wc -l')"
sh 'dumpsys display' | grep -oE 'type=(INTERNAL|EXTERNAL), valid=true, isActive=true, displayId=[0-9]+, [^,]*, [^,]*, orientation=[0-9]+, densityDpi=[0-9]+[^}]*' \
  | grep -oE 'type=[A-Z]+|displayId=[0-9]+|orientation=[0-9]+|logicalFrame=Rect\([0-9, -]*\)|physicalFrame=Rect\([0-9, -]*\)|deviceWidth=[0-9]+|deviceHeight=[0-9]+' \
  | paste -sd' ' - | sed 's/type=/\ntype=/g' | sed '/^$/d'
EXTID=$(sh 'dumpsys display' | grep -oE 'type=EXTERNAL, valid=true, isActive=true, displayId=[0-9]+' | grep -oE '[0-9]+$' | head -1)
if [ -n "$EXTID" ]; then
    echo "ext_id=$EXTID ext_rotation=$(sh "cmd window user-rotation -d $EXTID" | grep -oE 'lock [0-9]|free' | head -1)"
else
    echo "ext_id=none"
fi
echo "phone_watcher_pids=$(sh "pgrep -f 'phone-watche[r]' | tr '\n' ' '")"
