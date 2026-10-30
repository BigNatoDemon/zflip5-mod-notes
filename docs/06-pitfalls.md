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
