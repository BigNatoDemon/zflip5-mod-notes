# 08 设备内 adb（self-adb）：让手机重启后自己拉起 shell 守护

## 要解决的那一个断点

整套显示配置（画布 override、`cmd window user-rotation -d`、`set-ignore-orientation-request`）只有
**shell uid** 能写，而 Android 无 root 时没有任何开机 shell 钩子：init.rc 不可写，Termux:Boot 跑起来是
app uid 碰不到这些接口。于是手机端 watcher 一旦随重启消失，就只能连电脑补档。

self-adb 的做法：**App 里带一个 adb 客户端，连本机 adbd 监听的无线调试端口**。连上之后 App 就拿到
`uid=2000(shell) context=u:r:shell:s0`，可以替自己做所有 shell 操作，包括 `setsid` 拉起守护。
LADB / Bugjaeger 就是这个原理；本仓库选择不装第三方常驻全 shell 的应用，而是把这套能力并进自己的磁贴 App。

## 实测结论（SM-F7310 / One UI，2026-11-03）

| 事项 | 结果 |
|---|---|
| 本机 adbd 是否接受 loopback 连接 | ✅ `adb connect 127.0.0.1:<无线调试连接端口>` 成功，拿到 shell |
| 授权是否跨重启保留 | ✅ 重启后免配对码直连；`/data/misc/adb/adb_keys` 持久（恢复出厂才清） |
| 连接端口是否稳定 | ❌ 每次重开无线调试/每次重启都变（实测 34063 → 45459 → 43709）→ 必须自己发现 |
| 开机自动拉起 | ✅ 发出重启后 **31 秒**守护日志已出现 `开机恢复方向`，此时电脑还没连上 adb |

## 取材与校验

adb 二进制与依赖取自 Termux 官方仓库（AOSP platform-tools 的 Android 构建，上游 Apache-2.0）：

```
https://packages.termux.dev/apt/termux-main/pool/main/a/android-tools/android-tools_37.0.0p1-3_aarch64.deb
sha256 534e90d338bd432c06677cb402d0e9ed98a82a74de4bf5f90e643f15d8fc4274
```

逐个包对 `dists/stable/main/binary-aarch64/Packages` 索引里的 SHA256 校验后再解包。依赖 9 个：
`abseil-cpp brotli fmt libc++ liblz4 libprotobuf pcre2 zlib zstd`，一共抽出 113 个 `.so`。

> **坑：符号链接必须实体化。** deb 里 `libz.so.1`、`libzstd.so.1`、`libbz2.so.1.0` 这类是 tar 符号链接，
> 只按 basename 抓普通文件会得到 `CANNOT LINK EXECUTABLE ... library "libz.so.1" not found`。
> 解包时把 `issym()` 的成员按链接名再写一份实体文件。

## 打包要点

- `aapt2 link --jni` 在 build-tools 34 上**不可用**（报 `should only be used together with the --static-lib flag`）。
  本仓库用和塞 `classes.dex` 同一个 python 步骤，把 `jni/arm64-v8a/*` 写成 `lib/arm64-v8a/*`。
- `<application android:extractNativeLibs="true">` 必须打开：要 **exec** 这些库，必须它们在磁盘上。
  SELinux 只放行 App 执行自己 `nativeLibraryDir` 里的文件，所以 adb 改名成 `libadbexec.so` 放进去。
- adb 需要一个可写的 `HOME`（它会建 `$HOME/.android`），否则 `Cannot mkdir '//.android': Read-only file system` 直接崩。
  这里用 `getExternalFilesDir(null)`。
- `minSdk` 提到 26：`Adb.run()` 用了 `Process.waitFor(long, TimeUnit)`。
- 成品 APK 约 6.3 MB（adb 3.5 MB + 112 个 `.so` 12 MB，压缩后）。**`jni/` 与任何 `adbkey` 都不入库**（见 `.gitignore`）。

## 钥匙管理

必须让 **App 自己生成**钥匙：Android 11+ 下 App 看不见别的 uid（含 shell）在它
`Android/data/<pkg>/files/` 里创建的文件，所以 `adb push` 一把现成 keypair 进去，App 读不到。

1. App 首次运行执行 `adb keygen $HOME/.android/adbkey`。
2. 用电脑（或设备上的 shell）把**这把公钥对应的私钥复制出来**——反方向可读：shell 能读 App 自己建的文件。
3. 手机：设置 → 开发者选项 → 无线调试 → **输入配对码配对设备**，记下 6 位码和配对端口。
4. `adb pair 127.0.0.1:<配对端口> <6位码>`（用第 2 步那把私钥作 `HOME/.android/adbkey`）。
   配对端口 ≠ 连接端口，且配对只需一次。
5. 之后 `adb connect` 免码可用，跨重启有效。撤销：设置里"已配对的设备"列表逐条删除。

安全边界：这把钥匙 = 在你手机上以 shell 身份下命令的凭据。它只存在手机本地；**不要提交到仓库、不要打包分发**。
另外注意无线调试本身开着就是局域网攻击面（`ro.adb.secure=1` 时未授权设备连不上，但凭据泄露等于绕过这层）。

## 端口发现

Termux 构建的 adb **不支持 mDNS**（`adb mdns` 报 `mdns is not supported by this version of adb`），
所以端口要 App 自己查：

```java
NsdManager nsd = (NsdManager) ctx.getSystemService(Context.NSD_SERVICE);
nsd.discoverServices("_adb-tls-connect._tcp", NsdManager.PROTOCOL_DNS_SD, listener);
// onServiceFound -> resolveService -> onServiceResolved -> info.getPort()
```

解析到的端口缓存进 `$HOME/adbport`（App 自己写的文件，下次 NSD 失败可回退）。

> **坑：android-34 的 `android.jar` 里没有 `NsdManager.stopDiscovery`**（运行时存在），直接调用编译报
> "找不到符号"。只能反射调用，反射失败就算了——进程退出时系统会自己取消发现。

## 服务形态与开机链路

```
BOOT_COMPLETED → BootReceiver → startForegroundService(ReviveService)
   → Adb.ensureKey() → NSD 找端口 → adb connect → adb shell setsid sh /data/local/tmp/phone-watcher.sh &
   → adb shell "pgrep -f 'phone-watche[r]' | wc -l" 验活（==2 才算成功）
```

- **必须前台服务**：`am start-service` 在这台机上直接 `Error: app is in background uid null`。
  声明 `android:foregroundServiceType="specialUse"` 并给出 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`，
  权限要 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE`（+ 通知渠道）。
- 开机时 adbd 的无线端口未必已就绪（Wi-Fi 还没连上），所以 `ReviveService` 里重试 8 次、每次间隔 15 秒。
- 本次实测没有额外设置电池优化就能起来；如果哪天失效，先检查"设置 → 电池 → 该 App 的后台使用 → 不允许优化"。

## 和磁贴的联动

磁贴「修复画面」现在有两级动作：写触发文件 → 4 秒后检查文件是否被守护消费掉；
**没被消费 = 守护死了 → 直接走 self-adb 复活它**。实测：

```
01:13:21.674  fix trigger -> /storage/emulated/0/Android/data/<pkg>/files/fix
01:13:25.677  trigger not consumed -> revive via device-local adb
01:13:25.899  revive port=45459 connect=already connected ... alive=2
01:13:25      === watchdog 启动 === / === 手机端 watcher 启动 ===
```

守护侧配套改了一处：启动时把"上次已见的触发值"置空，于是残留的触发文件会被当作新请求消费掉，
等于开机额外做一次全量重放。

## 已知边界

- 只解决"重启后拉起守护"。刷机/恢复出厂会清掉配对，要重新走一次配对手续。
- App 被卸载或强制停止后，开机自启随之失效。
- 无线调试被关掉（或被 Auto Blocker 之类策略影响）时，`adb connect` 会失败——这是设计上的显式失败，
  日志里会留 `revive attempt N -> ...`。
- 这套机制给自己开了一个本机 shell 通道，属于"方便换面积"的取舍，用之前想清楚。
