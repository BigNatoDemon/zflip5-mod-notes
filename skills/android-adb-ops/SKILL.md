---
name: android-adb-ops
description: Connect to and keep reliable adb sessions with Android devices over Wi-Fi or USB from Windows - mDNS pairing, transport ids, offline triage, on-device shell daemons that survive disconnects (setsid + watchdog), and safe logcat/screencap capture. Use when adb connect fails or devices drop, when a shell loop must outlive the adb session, or when logcat/screencap/dumpsys output looks empty, corrupt, or misattributed.
---

# Android adb ops (Windows host)

## Connect

- Wireless: developer options → wireless debugging → "pair with code"; `adb pair <ip>:<pairport> <code>`.
  **Pairing port ≠ connect port**; `adb mdns services` lists both endpoints (`_adb-tls-pairing` / `_adb-tls-connect`).
- After pairing the device appears as an mDNS name. **Use `adb -t <transport_id>`** parsed from `adb devices -l`;
  `-s <serial>` fails for mDNS devices. Transport id changes on every reconnect - re-parse per invocation.
- Pairing keys survive phone reboot; wireless debugging **auto-reconnects after reboot** but **drops when the screen sleeps**.
  "device offline" ⇒ check screen state first.
- After flash/factory reset pairing is wiped ⇒ re-pair; FRP may gate setup.
- Git Bash: `export MSYS2_ARG_CONV_EXCL="*"` and pass **Windows paths** to push/install/pull
  (`/sdcard/x` otherwise becomes `C:/Program Files/Git/sdcard/x`; push "succeeds" with 0-byte result).
  `MSYS_NO_PATHCONV=1` does NOT fix push targets.

## Offline triage order

1. screen awake? 2. wireless debugging still on? 3. vendor "auto blocker"/security switch blocking adb writes
   (writes silently no-op while reads work; often no settings key exists - check UI manually)
   4. `adb mdns services` shows a connect endpoint? 5. wrong transport id cached?

## On-device shell daemons (no root)

- Start detached: `setsid sh /data/local/tmp/x.sh >/dev/null 2>&1 < /dev/null &`.
  **`nohup &` is not enough** - the process dies when the adb session closes.
- Watchdog pattern: wrapper loop re-spawns `sh "$0" worker`; wrapper cmdline must NOT contain the worker marker.
- Kill safely: `pkill -f 'x.sh worker'` (worker only) / `pkill -f 'x-watche[r]'` (all).
  **Self-match law**: a remote shell whose cmdline contains the bare script path will match `pkill/pgrep -f <path>`
  and kill itself. Use the bracket trick and keep bare paths out of the same call; split sed/push and pkill into separate adb calls.
- Liveness: `pgrep -f <name>`. **Never `ps -A | grep <script>`** - toybox ps NAME column is just `sh`.
- A shell daemon has shell uid: `wm`, `cmd window`, `settings put system/global`, `dumpsys` all work; it dies on reboot
  (no boot hook without root) - pair it with a PC-side cross-guard that relaunches it when adb reconnects.

## Capture discipline

- logcat: get the pid (`pidof <process>`) and filter by it; truncate lines (`cut -c1-160`); clear before a window (`logcat -c`);
  for user-timed actions capture to a file in background instead of fixed sleeps.
- screencap: `adb exec-out screencap -p > f.png` **corrupts** (stderr warning bytes in stream).
  Use `screencap -d <SurfaceFlinger long id> -p /sdcard/x.png` + pull; ids from `dumpsys SurfaceFlinger --display-id`;
  multi-display requires `-d`, and `-d 0` is invalid (needs the long id).
- dumpsys reading laws: empty output usually means the command/flag is wrong, not the condition false
  (`wm size -h`, unknown compat names, unsupported ps flags all print nothing useful);
  per-app window facts must come from the **package-qualified `Window{...}` block** in `dumpsys window windows`,
  never from a bare `grep CurrentConfiguration` (misattributes across packages).
