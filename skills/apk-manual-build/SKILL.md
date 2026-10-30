---
name: apk-manual-build
description: Build and sign an Android APK without Gradle using only SDK build-tools and a JDK - aapt2 compile/link, javac against android.jar, d8 to dex, inject classes.dex with python zipfile, zipalign, apksigner with a persistent keystore. Use when no Gradle/Android Studio is available, when building a tiny utility app (e.g. a Quick Settings TileService), or when a build must be reproducible from plain command lines.
---

# Manual APK build (no Gradle)

Toolchain: SDK `build-tools/<ver>/` (aapt2, d8, zipalign, apksigner) + `platforms/android-<api>/android.jar` + any JDK 17.
On Windows set `JAVA_HOME` and put its `bin` on PATH before calling the `.bat` tools.

## Pipeline

```bash
BT=<sdk>/build-tools/34.0.0; AJ=<sdk>/platforms/android-34/android.jar
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/base.apk -I "$AJ" --manifest AndroidManifest.xml build/res.zip --java build/gen
javac -nowarn -encoding UTF-8 -source 8 -target 8 -classpath "$AJ" -d build/obj \
      build/gen/<pkg path>/*.java src/<pkg path>/*.java
"$BT/d8" --release --min-api 24 --lib "$AJ" --output build/dex build/obj/<pkg path>/*.class
python - <<'PY'   # inject classes.dex (aapt2 link output has no dex)
import zipfile
zin=zipfile.ZipFile('build/base.apk'); zout=zipfile.ZipFile('build/unaligned.apk','w',zipfile.ZIP_DEFLATED)
for i in zin.infolist(): zout.writestr(i, zin.read(i.filename))
zout.write('build/dex/classes.dex','classes.dex'); zout.close(); zin.close()
PY
"$BT/zipalign" -f 4 build/unaligned.apk build/aligned.apk
"$BT/apksigner" sign --ks orient.jks --ks-pass pass:<pw> --key-pass pass:<pw> --out dist/app.apk build/aligned.apk
"$BT/apksigner" verify --print-certs dist/app.apk
```

## Hard-won rules

- **javac needs `-encoding UTF-8`** on CJK Windows locales (default GBK mangles Chinese string literals into compile errors).
- **Keystore must persist outside `build/`**. Regenerating it per build makes updates fail with
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signatures differ) and forces uninstall (losing tile placement + appops grants).
- PowerShell 5.1 reads BOM-less UTF-8 as GBK: any `.ps1` wrapper around this pipeline must be saved **UTF-8 with BOM + CRLF**,
  otherwise Chinese comments produce bogus syntax errors.
- Manifest still needs `package="..."` for raw aapt2 (AGP namespace rules don't apply); services with intent-filters need
  `android:exported="true"` on API 31+.
- Vector drawables in `res/drawable/` are enough for tile icons; tile labels may be set at runtime with literal strings.
- Record the cert SHA-256 in your notes: it is the only proof that future builds can update the installed app.

## Installing & wiring a TileService

```
adb install -r dist/app.apk
adb shell cmd appops set <pkg> WRITE_SETTINGS allow        # special-access perm, grantable from shell
adb shell cmd statusbar add-tile <pkg>/.<Service>          # One UI: only fills the candidate pool
adb shell "cmd statusbar set-tiles '<current list>,custom(<pkg>/.<Service>)'"   # puts it on the panel
```
- `sysui_qs_tiles` persists with a few seconds delay - re-read after a sleep before asserting.
- Test clicks: `adb shell cmd statusbar click-tile <pkg>/.<Service>`; if the service throws, SystemUI shows
  "运行错误" and the stack is in logcat (AndroidRuntime), not in the tile.
