---
name: apk-audit
description: Audit a third-party Android APK before installing - read badging (minSdk, zh-CN labels), scan dex for exfiltration endpoints and obfuscation, list native libs, verify signing certificate (debug key = re-signed), compare checksums against the official release, and check declared permissions against actual call sites. Use before installing any APK sourced outside the Play Store, or when judging whether a sideloaded tool phones home.
---

# APK audit checklist

Order matters: cheap static checks first; only install after they pass.

1. **Provenance**: prefer the vendor's GitHub release page; record URL + version tag.
   Compare `sha256`/`md5` against the checksum the vendor publishes (or against a known-good copy).
   Mismatch or no published checksum ⇒ treat as untrusted.
2. **Badging**: `aapt2 dump badging x.apk` (or `aapt dump badging`).
   - `minSdkVersion` vs device SDK (INSTALL_FAILED_OLDER_SDK otherwise)
   - **labels**: `application-label-zh-CN` - the default label line can be truncated or English-only and mislead identification
     (a "TV manager" tile was actually a different package once)
   - `native-code` ABIs vs device ABI
3. **Signing**: `apksigner verify --print-certs x.apk`.
   - Subject `CN=Android, O=Android` = **AOSP public debug key ⇒ re-signed build**; signature carries no provenance at all.
   - Compare cert SHA-256 with the vendor's published fingerprint when available.
4. **Dex scan for network endpoints** (no jadx needed):
   `unzip -p x.apk classes.dex | grep -aoE "https?://[A-Za-z0-9./?=_-]+" | sort -u`
   (multiple classes*.dex ⇒ loop). Classify each host: update check / telemetry / CDN / suspicious C2-like.
   Also grep for `getDeviceId|getSubscriberId|getInstalledPackages|AccessibilityService|DeviceAdmin|SYSTEM_ALERT_WINDOW` strings.
5. **Permissions vs behavior**: list `uses-permission`; for scary ones (READ_PHONE_STATE, MANAGE_EXTERNAL_STORAGE,
   QUERY_ALL_PACKAGES) check whether dex actually contains the matching call sites - declared-but-unused is common and lower risk.
6. **Native libs**: `unzip -l x.apk | grep '\.so$'`; unexpected native code = higher review bar; run `strings`-style grep for URLs too.
7. **Obfuscation/packing**: single small dex + heavy string encryption = packer ⇒ escalate scrutiny or refuse.
8. **Python-tool variants** (repo with venv): inspect `requirements.txt`, grep for uploads/telemetry, install with
   `pip install --no-deps` for the pieces you need after auditing deps.

## Install-time hygiene

- `adb install` (not `pm install` from /sdcard - SELinux blocks system_server reading fuse mounts; push to /data/local/tmp first if needed).
- Grant only what the workflow needs; record every `pm grant`/`appops set` you apply so restore is possible.
- Keep the audited APK + its checksum in the workspace so a later re-install is verifiable.

## Reporting format

One line per check: provenance / checksum / minSdk+ABI / cert subject+SHA256 / external hosts list / native libs / verdict.
State the verdict explicitly (install / install-with-cautions / refuse) and why.
