---
name: flip5-adb-ops
description: Operate and recover the Samsung Galaxy Z Flip5 (SM-F7310/b5q, TGY) media-box setup over adb - wireless pairing and transport quirks, mirrored-display canvas and rotation recipes (portrait-shaped wm size override, per-display scan rotation for the pivoted monitor), the orientation tile app, PC/phone watchers, and the post-flash restore package. Use when the user asks to connect to, configure, troubleshoot, or restore this phone, its casting/rotation/black-bar behavior, its quick-settings tiles, or anything under the workspace flip5-restore / orient-tile folders.
---

# Flip5 adb ops

## Overview

One phone (SM-F7310, TGY) used as a wall/monitor media box: inner screen mirrored over USB-C DP to a **physically pivoted (portrait) monitor**, driven by a Bluetooth remote and a self-built orientation tile. All state is reproducible from the workspace restore package; this skill encodes the non-obvious mechanics and the pitfalls that cost hours.

## Artifact map (workspace `<ws>`)

| Path | Role |
|---|---|
| `flip5-restore/README.md` | authoritative runbook (read this first for full procedures) |
| `flip5-restore/restore-flip5.ps1` | one-shot post-flash restore (apps, HOME role, disables, settings, canvas, phone watcher) |
| `flip5-restore/phone-watcher.sh` | on-phone watchdog+worker loop (shell uid, no PC needed) |
| `flip5-restore/state-snapshot.txt` | last captured ground truth (refresh after any change) |
| `orient-tile/` (v2.1+) | ships an arm64 **adb client** + its libs in `jni/arm64-v8a/`; `Adb.java` = exec + `keygen` + NSD port discovery; never commit `jni/` or any `.android/adbkey` |
| `flip5-restore/pc-watcher-archive/` | **retired PC watcher** (2026-11-02): `flip5-display-profile.ps1` + `register-autostart.ps1` + old log, kept for re-enablement; task `Flip5DisplayProfile` is unregistered |
| `orient-tile/` | tile app source + `build.sh` + persistent `orient.jks` + `dist/orient-tile.apk` |
| `sam/` | Odin firmware five-piece (CSC is OZS while phone is TGY - never flash its CSC slot); dir gets reorganized by the user, `ls` before use |

## Connect

- adb = `$SDK\Sdk\platform-tools\adb.exe`. In Git Bash: `export MSYS2_ARG_CONV_EXCL="*"` and pass **Windows paths** to push/install (`/d/...` becomes `C:/Program Files/Git/d/...` otherwise).
- Device enumerates as an mDNS name; **use `adb -t <transport_id>`** parsed from `adb devices -l`. `-s <serial>` fails; transport id changes every reconnect.
- After a flash/factory reset pairing is wiped: `adb mdns services` lists `_adb-tls-pairing`/`_adb-tls-connect` endpoints; **pairing port != connect port**; user reads the 6-digit code from the phone dialog, then `adb pair <ip>:<pairport> <code>`.
- Wireless debugging **auto-reconnects after phone reboot** (`adb_wifi_enabled` persists) but **drops whenever the screen sleeps** - "device offline" usually means screen off, not broken.
- Samsung `设置 → 安全与隐私 → 自动拦截程序 (Auto Blocker)` ON silently blocks adb write commands (PC watcher appears broken). No settings key, no package - check it manually first when writes "stop working".

## Display & rotation recipes (memorize)

- Mirror mode = **one shared logical canvas** for phone + external. `wm size` does **uniform fit only** (never anisotropic, no `-d`). Hence zero-sum: whichever screen's aspect the canvas matches fills; the other gets bars. Decided strategy **S2 = monitor always 1:1**, phone eats 456px bars.
- **Density 320dpi is load-bearing - never reset it**: `wm density 320` makes sw=800dp ≥ the 600dp tablet threshold so Youku/iQiyi/etc take tablet layouts; at 480dpi sw=533dp → phone layouts. Apps reporting "viewport 800x1280" is correct dp math (1600x2560 px ÷ 2), not a read bug. Watchers self-heal the density every loop.
- Override must be written in **portrait shape**: for a 2560x1600 monitor write `wm size 1600x2560`; in landscape the system swaps it to 2560x1600. Writing the landscape pair yields a 441px-wide strip.
- Monitor is **pivoted portrait but EDID still reports landscape** → set the mirror display's own scan rotation: `cmd window user-rotation -d <extId> lock N`, table by phone orientation r: **[3,2,1,0]** (r=0/e=3 verified upright+full). `extId` changes between sessions - parse `type=EXTERNAL, valid=true, isActive=true, displayId=` from `dumpsys display`.
- `cmd window set-ignore-orientation-request true` is **in-memory only**; without it portrait-locked apps pin the display back to portrait. Watchers re-apply it every loop.
- Rotation is owned by the tile app + `Settings.Secure flip5_orient_mode` (0-3, boot-restore source). Sensor is permanently off (`accelerometer_rotation 0`) by user demand; watchers never fight the tile, they only learn.
- Geometry law (stop re-deriving): mirrored image follows phone orientation. Portrait phone + landscape monitor = side bars on monitor; portrait phone + portrait monitor + correct ext rotation = both full; landscape phone + portrait monitor = upright content with big top/bottom bars. No strategy beats this.

## Watchers

- **Single layer: phone only.** `phone-watcher.sh` = watchdog wrapper + `worker` arg; worker killed → respawn in 2s. Its `ensure()` covers canvas, density, brightness, ignore-orientation, ext rotation table, plug/unplug - everything the old PC watcher did.
- PC watcher + logon task retired 2026-11-02 (duplicate logic, and every adb write it sent was a silent no-op whenever Auto Blocker was back on). Scripts archived, not deleted.
- Kill patterns: worker only `pkill -f 'phone-watcher.sh worker'`; everything `pkill -f 'phone-watche[r]'`. **Never put a bare script path and pkill/pgrep in the same adb shell command** - the remote shell matches its own cmdline and kills itself (split into two adb calls).
- Liveness: `pgrep -f phone-watche[r]`; **never `ps -A | grep`** (toybox ps shows only `sh`).
- Coverage matrix: worker killed → wrapper. Phone rebooted → **the `orient-tile` app revives it**: `BootReceiver` → `ReviveService` (foreground service; background starts are blocked by Samsung) → `NsdManager` resolves `_adb-tls-connect._tcp` for the current wireless-debugging port → bundled adb (`lib/arm64-v8a/libadbexec.so` + 112 .so, `extractNativeLibs=true`) connects to `127.0.0.1:<port>` with the app's own paired key → `setsid` the watcher. Measured: back up 31 s after reboot, no PC. Fallback if the app is missing: reconnect adb and run `restore-flip5.ps1`.

## Tile app

- Two tiles 顺时针/逆时针 (±90°, four orientations, always accel=0). Build: `orient-tile/build.sh` (aapt2/javac/d8/zipalign/apksigner; JDK `$SDK\jdk`; javac needs `-encoding UTF-8`). **`orient.jks` must persist** - new cert = `INSTALL_FAILED_UPDATE_INCOMPATIBLE` = uninstall+reinstall (loses tile slots + appops grant).
- Install extras: `cmd appops set dev.zflip5.orienttile WRITE_SETTINGS allow`; on One UI `cmd statusbar add-tile` only fills the candidate pool - put tiles into the panel with `cmd statusbar set-tiles '<list>,custom(pkg/.RotateCwTileService),custom(pkg/.RotateCcwTileService)'`; SystemUI persists the list with a few seconds delay.
- Apps **cannot write custom keys to Settings.System** (`IllegalArgumentException: You cannot keep your settings in the secure settings`, tile shows "运行错误"). Derive mode from `user_rotation`/`accelerometer_rotation` instead.

## Restore order (post flash / factory reset)

1. Pass FRP (account creds required - Odin+CSC wipe triggers it).
2. Turn **Auto Blocker off** (else every adb write silently fails).
3. Pair wireless debugging (code from phone dialog).
4. `restore-flip5.ps1` (idempotent; verifies firmware whitelist `F7310ZSU9HZIJ`/`F7310ZSS9GZI1`, installs Aerial/SmartTube/tile, HOME role, 15 disables, settings, canvas, phone watcher).
5. User plug/unplug test; refresh `state-snapshot.txt`. (No PC logon task any more - `phone-watcher.sh` is started by step 6b of the restore script.)
Known exceptions: `com.google.android.gms.supervision` and `com.samsung.android.knox.zt.framework` are protected on current firmware - shell disable throws; manual Settings UI only. Never flash `sam/` CSC_OZS (region change + wipe).

## Verify (ASCII-safe one-liner)

Run `scripts/flip5-probe.sh` - prints transport, firmware, canvas, rotation triple, mode key, ignore-orientation, both viewports, watcher count. For per-app window geometry use `dumpsys window windows` and grep the **package-qualified `Window{...}` block** - bare `grep CurrentConfiguration` mis-attributes windows across packages (this exact mistake produced a wrong "bilibili fills landscape" conclusion once).

## Resources

- `scripts/flip5-probe.sh` - invariant dump, ASCII-safe, auto-detects transport
- `references/pitfalls.md` - the full hard-won pitfall list (encoding, self-match, empty-output traps, logcat filtering, screencap)
- `references/runbook.md` - condensed command cookbook (display, rotation, watchers, tile, bluetooth remote diagnosis)
