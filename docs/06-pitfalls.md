# 06 坑清单（每条都真踩过）

## shell / adb

- Git Bash 路径改写：`MSYS2_ARG_CONV_EXCL="*"` + Windows 路径，否则 `/sdcard` 变 `C:/Program Files/Git/sdcard`
- mDNS 设备必须 `-t <transport_id>`；`-s <serial>` 报 not found；transport 每连必变
- **自匹配杀进程（三次）**：远程 shell 命令里同时含裸脚本路径与 `pkill/pgrep -f` 会杀掉执行命令的自己；
  PC 侧按命令行过滤 powershell 时过滤串出现在自己的 `-Command` 里同样自杀。
  对策：括号 trick `'phone-watche[r]'`、过滤串拼接构造、排除 `$PID`、把 sed/push 与 pkill 拆成两次调用
- `adb exec-out screencap -p > f.png` 会把 warning 字节灌进 PNG 导致损坏；
  正确：`screencap -d <SurfaceFlinger 长id> -p /sdcard/x.png` 再 pull；长 id 来自 `dumpsys SurfaceFlinger --display-id`
- 多屏时 `screencap` 必须带 `-d`；`-d 0` 报 invalid，要传 SF 长 id

## 读数陷阱

- **空输出 ≠ 条件不成立**：`wm size -h`、`am compat query IGNORE_ORIENTATION`（Android 17 已无此名）、
  toybox `ps -o ETIME` 都会空/报错。空输出先怀疑命令本身
- `ps -A | grep <脚本名>` 永远空（NAME 列只有 `sh`）→ 用 `pgrep -f`
- `dumpsys display` 的 viewport `logicalFrame/physicalFrame` 满 ≠ 镜像画面满：
  镜像的信箱黑边在帧里看不见，判断铺满要靠比例计算或截图
- 裸 `grep CurrentConfiguration` 会**串包**（读到别的窗口的配置）→ 用 `dumpsys window windows`
  里带包名的 `Window{...}` 块定位
- logcat 洪水：`RoundedCornerOffset Pair{0 0}`、巨型 PersistableBundle 行；按蓝牙进程 PID 过滤 + `cut -c1-160`；
  用户操作计时用后台落盘捕获，别用固定 sleep 窗口（时间窗对不上=白抓）

## 编码

- PowerShell 5.1 把无 BOM 的 UTF-8 当 GBK 读 → 中文注释炸语法。所有 .ps1 必须 **UTF-8 BOM + CRLF**
  （每次编辑后用 python 重写一遍）
- javac 默认 GBK → `-encoding UTF-8`
- 读日志先试 utf-16 再试 utf-8（不同时期的写入编码不同）

## 显示 / 旋转

- `wm size` override 按**自然竖屏方向**解释；横屏画布要写竖屏形状
- `wm size` 等比 fit、无各向异性、无 `-d`；"手机压缩填满 + 外接 1:1" 不存在
- `set-ignore-orientation-request` 内存态；没有它竖屏锁 App 会把整屏钉回竖屏
- 密度 reset 回 480 会丢平板分支（sw 跌破 600dp）——320 是负载配置
- 外接镜像屏的 displayId 每次会话可能变（见过 6/7/10），别写死
- `cmd window user-rotation -d <extId>` 只旋转镜像画面，不会重新排版；竖置显示器靠它校正方向

## 包管理 / 构建

- `pm disable` 不带 `--user 0` → SecurityException；个别包在新固件受保护，禁用抛异常（容忍+标注）
- APK 更新必须同证书：密钥库丢了只能卸载重装（丢磁贴位置与 appops 授权）
- One UI `cmd statusbar add-tile` 只进候选池；上屏要 `set-tiles` 整表重写；SystemUI 落盘有延迟
- App 写 `Settings.System` 自定义键 = IllegalArgumentException + 磁贴"运行错误"
- `force_resizable_activities` / `am compat FORCE_RESIZE_APP` **都压不住**固定 `screenOrientation` 的信箱旋转

## 蓝牙

- 天猫魔盒类 BLE 遥控"第二次要重新配对"：手机 LE 地址轮换（RPA ~7-14min）+ 遥控 LE Legacy 不解析 IRK
  → 定向广播喊不到轮换后的手机 → 10s 直连超时（`HidHostService msg.what=30`），全程无 SMP 失败日志
- 电视盒子用固定 LE 地址所以正常——"电视好用手机不好用"的根因
- 手机侧无开关可关 RPA（隐私特性，需 root/厂商属性）；缓解=遥控广播态组合键或 USB 接收器

## App ↔ shell 通道（One UI / Android 11+）

- App **写**自定义 `Settings.System` 键一律抛 `IllegalArgumentException: You cannot keep your settings in the secure settings.`（`SettingsProvider.warnOrThrowForUndesiredSecureSettingsMutationForTargetSdk`）；**把 targetSdk 从 34 降到 28 不解决**。白名单公开键（`user_rotation`、`accelerometer_rotation`）可以写。
- App **读**自定义键静默返回默认值（不报错）→ 表现为"永远读到 0"，别误判成守护掉线。
- shell 在 App 的 `Android/data/<pkg>/files/` 里建的文件，App 看不见，**chmod 666 也没用**（按 uid 隔离，不看 mode）。反方向可行：App 建的文件 shell 能读能删。
- 所以唯一可用的触发通道 = **App 写自己外部目录里的文件，shell 轮询读取**；存活信号用"请求文件是否已被 shell 删除"表达。

## Quick Settings 磁贴

- `STATE_UNAVAILABLE` 的磁贴**点击被 One UI 吞掉** → 磁贴要永远 `STATE_ACTIVE`，否则"读不到心跳→置灰→再也点不动"自锁。
- 重装 APK 后 SystemUI 沿用缓存的旧 tile 状态且不重新 bind（日志只有 `handleSetListening true`，没有 `Start proc`）。修法：把该磁贴从 `sysui_qs_tiles` 摘掉再写回；**副作用是 One UI 会重排面板位置**。
- `cmd statusbar click-tile <spec>` 在本机是空操作，不能当探针。真点击要 `cmd statusbar collapse; sleep 1; cmd statusbar expand-settings; sleep 2; input tap X Y` 连成一条 adb 调用（面板会自己收起，且息屏后一切 tap 无效）。
- 别为验证磁贴外观去猜坐标：`uiautomator dump` 拿不到 QS 磁贴节点。

## 自匹配探针（第 N 次记录）

- 远端 shell：同一条命令里既含裸脚本路径又含 `pkill/pgrep -f` 会杀掉执行命令的自己 → 拆两次调用，或用 `'phone-watche[r]'`。
- PowerShell：`Get-CimInstance ... -like '*flip5*display*profile*'` 会匹配到**执行查询的那个 shell 自身命令行**（里面字面含任务名），于是"杀了又活"像是进程重生。用 `'flip5-display-profil'+'[e].ps1'` 且排除 `$PID`。
- `adb reboot` 在有多个 transport 时报 `more than one device/emulator` 而**静默不重启**，若后面接了 `; sleep` 看起来就像"重启没生效"。要先 `adb devices` 数清楚，用 `-s <serial>`/`-t <id>` 指定。
