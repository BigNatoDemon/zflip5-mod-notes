# Pitfalls (each one cost real time; verify before re-deriving)

## Shell / transport
- Git Bash mangles POSIX-looking paths: `export MSYS2_ARG_CONV_EXCL="*"` and use `E:\...`/`D:\...` for adb push/install/pull targets.
- Device = mDNS name; always `adb -t <transport_id>` (parse `adb devices -l`). `-s <serial>` → "device not found". Transport id changes per reconnect; scripts must re-parse it every run.
- Pairing port ≠ connect port. After flash, `adb mdns services` shows both endpoints; user supplies the 6-digit code from the phone dialog.
- Screen sleep drops wireless adb → "device offline" ≠ broken. Reboot does NOT drop it (auto-reconnect verified).
- Auto Blocker (设置→安全与隐私→自动拦截程序) ON = adb writes silently no-op. Undetectable via adb (no key, no package). Check manually first.

## Self-match kills (three separate incidents)
- Remote shell: a command containing BOTH a bare script path and `pkill/pgrep -f` kills the shell running it. Split into separate adb calls; or use bracket trick `'phone-watche[r]'` AND keep the bare path out of that same call.
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
