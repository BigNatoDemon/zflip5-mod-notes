# 01 无线 adb 接入

## 基本事实

- 设备以 **mDNS 名**出现（`adb-<serial>-<rand>._adb-tls-connect._tcp`）。
  **用 `adb -t <transport_id>`**（从 `adb devices -l` 解析）；`-s <serial>` 报 device not found。
  transport_id 每次重连都变，脚本必须每轮重新解析。
- **重启后无线调试自动回连**（`Settings.Global adb_wifi_enabled` 持久）。
- **熄屏即掉线**：无线 adb 随屏幕休眠断开。"device offline" 先怀疑熄屏，再怀疑配置。
- Git Bash 下：`export MSYS2_ARG_CONV_EXCL="*"`，且 push/install/pull 传 **Windows 路径**
  （`/d/...` 会被改写成 `C:/Program Files/Git/d/...`）。

## 刷机/恢复出厂后重新配对

配对密钥随 /data 清空。步骤：

1. 手机：设置 → 关于手机 → 软件信息 → 连点"版本号"7 次 → 开发者选项 → 无线调试 → 打开
2. 电脑：`adb mdns services` 能看到 `_adb-tls-pairing` 与 `_adb-tls-connect` 两个端点；
   **配对端口 ≠ 连接端口**，别拿连接端口去 pair
3. 手机点"使用配对码配对设备"，把弹窗里的 `IP:端口` 与 6 位码输入电脑：
   `adb pair <ip>:<pairport> <code>`（弹窗几十秒就换码，超时重点一次）
4. 之后 `adb devices -l` 自动出现设备

## Auto Blocker（最阴的一个开关）

Samsung「设置 → 安全与隐私 → **自动拦截程序 (Auto Blocker)**」开启时会**拦截经 USB/adb 下发的命令与侧载安装**。
表现：PC 端 watcher 的所有写命令（`wm size` / `cmd window` / `settings put`）静默失败，看起来像"配置莫名丢了"。

- 该开关**没有对应 settings 键、没有独立包**，adb 读不到也改不了，只能人工在设置里确认
- 刷机/恢复出厂后可能回到默认开启 → 恢复流程第一步先关它
- 手机端 watcher 走本机 shell，**不受它影响**（这是保留手机端 watcher 的理由之一）

## 离线排查顺序

1. 手机亮屏了吗（熄屏=掉线）
2. 无线调试还开着吗（恢复出厂后需重配）
3. Auto Blocker 是否被打开（写命令失败但读命令正常时优先怀疑它）
4. `adb mdns services` 有无 `_adb-tls-connect` 条目（没有=手机侧服务没起）
