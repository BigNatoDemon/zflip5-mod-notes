# Command cookbook

All commands assume `ADB=/d/Android/Sdk/platform-tools/adb.exe`, `export MSYS2_ARG_CONV_EXCL="*"`, and `T` = transport id parsed from `adb devices -l`. Run helper: `sh(){ adb -t $T shell "$1" 2>&1 | tr -d '\r'; }`.

## Connect / identity
```
adb devices -l                                  # parse transport_id:N
adb mdns services                               # pairing + connect endpoints after a flash
adb pair <ip>:<pairport> <6digit>               # code from phone dialog
sh "getprop ro.build.version.incremental; getprop ro.oem.key1; getprop ro.boot.warranty_bit"
```
Expected: incremental in {F7310ZSU9HZIJ, F7310ZSS9GZI1}, key1=TGY, warranty_bit=0.

## Display state (the four numbers that matter)
```
sh "wm size"                                    # Override size: <portrait-shaped pair>
sh "dumpsys display" | grep -oE 'type=(INTERNAL|EXTERNAL), valid=true, isActive=true[^}]*'
sh "cmd window get-ignore-orientation-request"
sh "cmd window user-rotation -d <extId>"        # extId from the EXTERNAL viewport line
```
Fill check by aspect math: canvas presented W/H vs panel 1080x2640 (r even) / 2640x1080 (r odd); bars = the leftover. Screenshot for visual truth:
```
sh "screencap -d 4630946592180194435 -p /sdcard/s.png"   # inner display SF id
adb -t $T pull /sdcard/s.png E:\tmp\s.png
```

## Apply the decided profile (S2, pivoted portrait monitor)
```
sh "wm size 1600x2560"                          # = monitor 2560x1600 in portrait shape
sh "cmd window set-ignore-orientation-request true"
sh "cmd window user-rotation -d <extId> lock <EXT_ROT[r]>"   # EXT_ROT=[3,2,1,0]
sh "settings put system accelerometer_rotation 0"
sh "settings put system screen_brightness_mode 0; settings put system screen_brightness 1"
```
Unplug profile:
```
sh "cmd window set-ignore-orientation-request reset"
sh "wm size reset"
sh "settings put system screen_brightness_mode 1"
```

## Rotation (tile-owned)
```
sh "settings get system user_rotation"          # 0..3, the live mode
sh "settings get secure flip5_orient_mode"      # boot-restore source
sh "settings put system user_rotation <0..3>"   # manual set (tile does the same)
```
Tile clicks from shell for testing: `sh "cmd statusbar click-tile dev.zflip5.orienttile/.RotateCwTileService"`.

## Watchers
```
# phone
adb -t $T push <ws>\flip5-restore\phone-watcher.sh /data/local/tmp/phone-watcher.sh
sh "sed -i 's/\r$//' /data/local/tmp/phone-watcher.sh"     # separate call!
sh "pkill -f 'phone-watche[r]'"                            # separate call!
sh "setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &"
sh "pgrep -f 'phone-watche[r]' | tr '\n' ' '"               # expect 2 (wrapper+worker)
sh "tail -5 /data/local/tmp/flip5-profile-phone.log"
# PC watcher retired 2026-11-02; scripts archived under <ws>\flip5-restore\pc-watcher-archive\
# To bring it back: copy the two .ps1 out, then
#   powershell -File <archive>\register-autostart.ps1
#   Get-ScheduledTask Flip5DisplayProfile | % State
# (both scripts hardcode <ws> paths - fix them if you move things)
```

## Tile app rebuild / reinstall
```
bash <ws>/orient-tile/build.sh                  # needs $SDK\jdk on PATH via JAVA_HOME inside
adb -t $T install -r <ws>\orient-tile\dist\orient-tile.apk
sh "cmd appops set dev.zflip5.orienttile WRITE_SETTINGS allow"
# refresh panel list (read, dedupe orienttile, append both, write; re-read after 4s)
sh "settings get secure sysui_qs_tiles"
sh "cmd statusbar set-tiles '<list>'"
```

## Restore package (post flash)
```
powershell -File <ws>\flip5-restore\restore-flip5.ps1          # add -DryRun to preview; step 6b starts the phone watcher
```
Preconditions: FRP passed, Auto Blocker OFF, wireless debugging paired.

## Bluetooth remote diagnosis (天猫魔盒 HOGP "alibaba")
```
sh "dumpsys bluetooth_manager" | grep -aE 'Bonded devices|E1:02|shim::record|HOGP'
sh "logcat -c"                                   # then user taps connect + presses keys
sh "logcat -d" | grep -aE " $(pidof com.android.bluetooth) |btif_hh|bta_hh|HidHostService" | cut -c1-160
```
Signature of the known failure: `connectEnabledProfile(HidHostService)` → `bta_hh_connect_upgrade: Upgrading to direct connection` → state 0→1 → **10.0s** → `msg.what=30` → 1→0, with zero remote advertisements and zero SMP lines.

## Odin (reference only; device is lock-locked)
Five-piece in `<ws>/sam/`: flash BL/AP/CP only. CSC_OZS ≠ phone TGY → never flash CSC slot. Magisk-patched AP = `secure check fail : init_boot()` on this locked bootloader; do not attempt.
