# 03 四向旋转磁贴 App（orient-tile）

## 为什么需要它

- 用户要求**不用传感器**（`accelerometer_rotation` 恒 0，碰手机不要乱转），方向只能显式切
- 系统自带磁贴只有"自动旋转/方向锁定"两态，且锁定方向取决于当前姿态，不能四向直达
- 无 root 下 App 想写 `Settings.System` 需要 `WRITE_SETTINGS`（特殊访问授权，adb 可代授）

## 设计

- 两个 Quick Settings 磁贴：**顺时针转 / 逆时针转**，每次 ±90°，四向循环（竖0/横1/倒竖2/倒横3）
- 只写两个**系统已知键**：`user_rotation` + `accelerometer_rotation`(恒0)
  —— **App 写 `Settings.System` 自定义键会抛
  `IllegalArgumentException: You cannot keep your settings in the secure settings`**，磁贴报"运行错误"
- 模式事实源分两层：
  - 运行时 = 那两个系统键（磁贴与系统磁贴共享）
  - 跨重启 = `Settings.Secure flip5_orient_mode`（0-3，**shell 写**；`user_rotation` 重启会回 0，靠 watcher 按它恢复）
- watcher 只"学习"磁贴的改变，不主动改旋转 → 两套逻辑不打架

## 构建（不经过 Gradle）

`orient-tile/build.sh`：aapt2 compile/link → javac（**必须 `-encoding UTF-8`**，locale 是 GBK）→
d8 → python 合入 classes.dex → zipalign → apksigner。JDK 与 build-tools 路径用环境变量 `JDK`/`SDK` 覆盖。

**`orient-tile/orient.jks` 密钥库必须永久保留**：换证书 = `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，
只能卸载重装（会丢磁贴位置与 appops 授权）。

## 安装与上屏

```
adb install orient-tile/dist/orient-tile.apk
adb shell cmd appops set <pkg> WRITE_SETTINGS allow
adb shell cmd statusbar add-tile <pkg>/.RotateCwTileService     # One UI 上只进候选池
adb shell cmd statusbar add-tile <pkg>/.RotateCcwTileService
# 面板里没有就整表重写（先读现表、去重、追加两个 custom 条目）：
adb shell "cmd statusbar set-tiles '<list>,custom(<pkg>/.RotateCwTileService),custom(<pkg>/.RotateCcwTileService)'"
```

- SystemUI 落盘有几秒延迟，set-tiles 后立刻读 `sysui_qs_tiles` 会少算
- 验证点击：`adb shell cmd statusbar click-tile <pkg>/.RotateCwTileService` 在 One UI 上**会**派发 onClick
  （早期"点了没反应"其实是旧版 onClick 崩溃被 SystemUI 吞掉）；崩溃看 `logcat -s OrientTile:V` 与 AndroidRuntime

## 权限面

仅声明 `WRITE_SETTINGS`；无网络权限、无无障碍、无自启接收器。自签证书（指纹见 apksigner verify）。
