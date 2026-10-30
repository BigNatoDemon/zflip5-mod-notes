#!/usr/bin/env bash
# 手工打包 orient-tile（不经过 Gradle）：aapt2 -> javac -> d8 -> zip -> zipalign -> apksigner
set -e
cd "$(dirname "$0")"
SDK=${SDK:-/d/Android/Sdk}   # 可用环境变量 SDK / JDK 覆盖
BT=$SDK/build-tools/34.0.0
AJ=$SDK/platforms/android-34/android.jar
export JAVA_HOME=${JDK:-/d/Android/jdk}
export PATH="$JAVA_HOME/bin:$PATH"

rm -rf build dist
mkdir -p build/gen build/obj build/dex dist

echo "== aapt2 compile/link"
"$BT/aapt2.exe" compile --dir res -o build/res.zip
"$BT/aapt2.exe" link -o build/base.apk -I "$AJ" --manifest AndroidManifest.xml build/res.zip --java build/gen

echo "== javac"
javac -nowarn -encoding UTF-8 -source 8 -target 8 -classpath "$AJ" -d build/obj \
  build/gen/dev/zflip5/orienttile/*.java src/dev/zflip5/orienttile/*.java

echo "== d8"
"$BT/d8.bat" --release --min-api 24 --lib "$AJ" --output build/dex build/obj/dev/zflip5/orienttile/*.class

echo "== 合入 classes.dex"
python - <<'PY'
import zipfile, shutil
src = 'build/base.apk'
dst = 'build/unaligned.apk'
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    zout.writestr(item, zin.read(item.filename))
zout.write('build/dex/classes.dex', 'classes.dex')
zout.close(); zin.close()
print('classes.dex added')
PY

echo "== zipalign + sign"
"$BT/zipalign.exe" -f 4 build/unaligned.apk build/aligned.apk
# 密钥库必须持久：换证书会导致 INSTALL_FAILED_UPDATE_INCOMPATIBLE
if [ ! -f orient.jks ]; then
  keytool -genkeypair -keystore orient.jks -storepass android -keypass android \
    -alias orient -keyalg RSA -keysize 2048 -validity 3650 -dname "CN=flip5-orient-tile, OU=local, O=local" 2>/dev/null
  echo "generated NEW keystore orient.jks (keep it forever)"
fi
"$BT/apksigner.bat" sign --ks orient.jks --ks-pass pass:android --key-pass pass:android \
  --out dist/orient-tile.apk build/aligned.apk
"$BT/apksigner.bat" verify --print-certs dist/orient-tile.apk | head -4
ls -la dist/orient-tile.apk
