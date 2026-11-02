# Pitfalls (each one cost real time; verify before re-deriving)

## Shell / transport
- Git Bash mangles POSIX-looking paths: `export MSYS2_ARG_CONV_EXCL="*"` and use `E:\...`/`D:\...` for adb push/install/pull targets.
- Device = mDNS name; always `adb -t <transport_id>` (parse `adb devices -l`). `-s <serial>` → "device not found". Transport id changes per reconnect; scripts must re-parse it every run.
- Pairing port ≠ connect port. After flash, `adb mdns services` shows both endpoints; user supplies the 6-digit code from the phone dialog.
- Screen sleep drops wireless adb → "device offline" ≠ broken. Reboot does NOT drop it (auto-reconnect verified).
- Auto Blocker (设置→安全与隐私→自动拦截程序) ON = adb writes silently no-op. Undetectable via adb (no key, no package). Check manually first.

## Self-match kills (three separate incidents)
- Remote shell: a command containing BOTH a bare script path and `pkill/pgrep -f` kills the shell running it. Split into separate adb calls; or use bracket trick `'phone-watche[r]'` AND keep the bare path out of that same call.
- Same trap on the Windows side: a `Get-CimInstance Win32_Process` filter whose `-match`/`-like` pattern text also appears in your own command line (e.g. the task name `Flip5DisplayProfile` matching `*flip5*display*profile*`) makes the probe kill itself, and the respawning pids look like the watcher refuses to die. Use a bracketed pattern (`flip5-display-profil` + `[e].ps1`) and exclude `$PID`; the query command line never contains that literal.
- PC PowerShell: filtering `Win32_Process` by a pattern that appears in your own `-Command` string kills your own powershell mid-pipeline (output truncates mysteriously). Build patterns from concatenated parts and exclude `$PID`.

## Empty/odd output traps
- Empty output often means the command is broken, not the condition false: `wm size -h` → "bad size"; `am compat query IGNORE_ORIENTATION` → unknown change on Android 17; `ps -A -o ETIME` unsupported by toybox.
- `ps -A | grep <script>` never matches (NAME column = `sh`). Use `pgrep -f`.
- `dumpsys display` viewport frames being full does NOT mean the mirrored image fills: mirror letterboxing is invisible in frames. Judge fill by aspect math or a screenshot.
- Bare `grep CurrentConfiguration` mis-attributes windows across packages. Use `dumpsys window windows` and the package-qualified `Window{pid... pkg/Activity}` block.
- logcat floods: `RoundedCornerOffset Pair{0 0}` spam, giant PersistableBundle lines. Filter by the bluetooth pid (`pidof com.android.bluetooth`) and `cut -c1-160`. Clear (`logcat -c`) before a capture window; for user-timed actions capture to a file in background instead of a fixed sleep window.
- `adb exec-out screencap -p > f.png` corrupts (warning bytes in stream). Use `screencap -d <SurfaceFlinger long id> -p /sdcard/x.png` then pull; ids from `dumpsys SurfaceFlinger --display-id`.

## Encoding
- PowerShell 5.1 reads BOM-less UTF-8 as GBK → Chinese comments break parsing with bogus syntax errors. All .ps1 here must be UTF-8 **with BOM** + CRLF (python rewrite after every Edit).
- javac defaults to GBK on this locale → `-encoding UTF-8` or Chinese strings fail compilation.
- Log files: watcher log is UTF-16 (Tee) / UTF-8 (Add-Content -Encoding UTF8) depending on era; try utf-16 then utf-8 when reading.

## Display / rotation
- `wm size` override is interpreted in **natural portrait space**; write the portrait-shaped pair for a landscape canvas. Uniform fit only; no anisotropic stretch; no `-d`.
- `cmd window set-ignore-orientation-request` is in-memory (lost on system_server restart / reboot). Without it, portrait-locked apps pin the display.
- Pivoted monitor + landscape EDID → per-display scan rotation `cmd window user-rotation -d <extId> lock N`; extId changes per session (seen 6,7,10); table [3,2,1,0] by phone r.
- `user_rotation` does NOT survive reboot (resets 0); `Settings.Secure flip5_orient_mode` is the boot-restore source, maintained by watchers.
- Mirror geometry zero-sum: portrait phone ⇒ landscape monitor bars; portrait monitor + landscape phone ⇒ bars. No strategy fixes both.
- `force_resizable_activities` and `am compat FORCE_RESIZE_APP` do NOT override a fixed `screenOrientation` (bilibili stays letterboxed). Don't re-test.
- Density trial data (2026-10-29): 400dpi → sw640dp + size class `lrg` (drops below `xlrg`; sw600dp resource qualifier still matches) and tablet branch then needs canvas width ≥1500px (a 1440p monitor would fall back to phone layout). 320dpi → sw800dp + `xlrg`, safe down to 1200px canvas. Kept at 320.

## Packages / installs
- Apps cannot write custom keys to `Settings.System` (IllegalArgumentException, tile shows 运行错误). Derive state from known keys.
- APK updates require the SAME keystore: keep `orient-tile/orient.jks` forever; new cert = uninstall+reinstall (loses QS tile slots + appops grants).
- One UI: `cmd statusbar add-tile` only fills the candidate pool; active panel needs `set-tiles` with the full comma list; SystemUI persists with a few seconds delay (immediate re-read undercounts).
- `pm disable` without `--user 0` → SecurityException. `com.google.android.gms.supervision` + `com.samsung.android.knox.zt.framework` throw on disable in current firmware (protected); tolerate + note.
- Odin: never flash `sam/` CSC_OZS onto the TGY phone (region change + wipe). `sam/` layout is reorganized by the user between sessions - `ls` first.
- FRP: any CSC-wiping flash demands the previously synced Google/Samsung account at setup. No adb bypass.

## Bluetooth remote (天猫魔盒 BLE HOGP, name "alibaba")
- Symptom "paired but tap does nothing, must re-pair": phone initiates direct LE connect, 10s timeout (`HidHostService msg.what=30`), zero advertisements from remote, NO SMP failures → not a key mismatch.
- Root cause model: phone rotates its LE address (RPA, ~7-14min); remote is LE-Legacy (`SecureConn:F`) and only directs wake advertisements at the address it bonded with → stale target → silence. TV boxes use static addresses, hence "works on TV".
- Mitigations: combo-key broadcast mode (主页+菜单 / OK+返回 3-5s) at connect time, or a USB-C dongle remote. Phone-side has no fix (rotation is a privacy feature, no knob, no root).

## App <-> shell 通道（One UI / Android 11+）

- App **写**自定义 `Settings.System` 键一律抛 `IllegalArgumentException: You cannot keep your settings in the secure settings.`；把 targetSdk 从 34 降到 28 **不解决**。白名单公开键（`user_rotation`、`accelerometer_rotation`）可以写。
- App **读**自定义键静默返回默认值（不报错）—— 表现为"永远读到 0"，别误判成守护掉线。
- shell 在 App 的 `Android/data/<pkg>/files/` 里创建的文件，App 看不见；**chmod 666 也没用**（按 uid 隔离）。反方向可行：App 建的文件 shell 能读能删。
- 结论：**唯一可用的触发通道 = App 写自己外部目录里的文件，shell 轮询读取**；反向（shell 通知 App）不可得。存活信号用"请求文件是否已被 shell 删除"表达。
- TileService 状态陷阱：`STATE_UNAVAILABLE` 的磁贴**点击被 One UI 吞掉** → 永远保持 `STATE_ACTIVE`，否则"读不到心跳→置灰→再也点不动"自锁。
- 重装 APK 后 SystemUI 用缓存的旧 tile 状态、不重新 bind（日志里只有 `handleSetListening true`，没有 `Start proc`）。修法：把该磁贴从 `sysui_qs_tiles` 摘掉再写回（副作用：One UI 重排面板位置）。
- `cmd statusbar click-tile <spec>` 在本机是空操作，不能当探针。真点击要用 `cmd statusbar collapse; sleep 1; cmd statusbar expand-settings; sleep 2; input tap X Y` 连成一条 adb 调用（面板会自己收起）。
