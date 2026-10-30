# zflip5-mod-notes

把一台 **Samsung Galaxy Z Flip5（SM-F7310）** 改造成"竖置显示器 + 手机"的镜像媒体盒的完整方法学：
显示画布配方、四向旋转磁贴、双端 watcher 自愈、刷机后一键恢复、以及一路踩出来的坑清单。

> 适用前提与本文相同：One UI 8/9、**bootloader 锁死**（无 root、无 DeX、无第三方 recovery）、
> 手机经 USB-C DP **镜像**（mirror）到外接显示器、显示器**物理竖置**但 EDID 仍报横屏。
> 所有结论都在真机上用 `dumpsys`/日志/截图验证过，验证日期与固件版本见各文档。

## 拓扑

```
[蓝牙遥控(天猫魔盒 HOGP)] --BLE--> [Z Flip5 内屏 1080x2640]
                                      |  USB-C DP AltMode = 镜像(单画布)
                                      v
                          [外接显示器 2560x1600, 物理竖置]
[Windows 笔记本] --无线 adb(mDNS/TLS)--> 手机 shell：负责恢复/自愈/构建
```

## 仓库地图

| 路径 | 内容 |
|---|---|
| `docs/01-connect.md` | 无线 adb 接入：配对、transport、掉线规律、Auto Blocker |
| `docs/02-display-recipe.md` | 镜像几何定律、画布 override 写法、密度 320 的意义、外接屏独立旋转表 |
| `docs/03-rotation-tiles.md` | 自研顺/逆时针磁贴 App：设计、构建、安装、模式事实源 |
| `docs/04-watchers.md` | PC + 手机双 watcher：职责、自愈、watchdog、覆盖矩阵 |
| `docs/05-restore.md` | 刷机/恢复出厂后的一键恢复与存活性矩阵 |
| `docs/06-pitfalls.md` | 坑清单（每条都是真踩过的） |
| `docs/07-bluetooth-remote.md` | 蓝牙遥控"第二次连接要重新配对"的定位与模型 |
| `scripts/` | 四个运维脚本（路径已参数化，见各文件头注释） |
| `orient-tile/` | 磁贴 App 完整源码 + 手工打包脚本（不依赖 Gradle） |
| `skill/flip5-adb-ops/` | 可安装的 Qoder Skill 版本（发布变体：路径占位化）；本机另有一份带真实路径的工作副本 |

## 三条最重要的结论

1. **镜像 = 单画布**。手机和外接屏永远显示同一张图，`wm size` 只做等比缩放。
   于是"哪块屏铺满"是零和选择；本仓库定案 = 画布取外接屏比例（显示器 1:1），手机吃黑边。
2. **竖置显示器 + 横屏 EDID** 需要给外接 display 单独设扫描旋转
   （`cmd window user-rotation -d <extId> lock N`），并按手机方向联动（表 `[3,2,1,0]`）。
3. **密度 320dpi 是负载配置**：它让 `sw=800dp ≥ 600dp`，视频类 App 才走平板布局分支；
   reset 回 480 会悄悄掉回手机布局。

## 快速开始（已有一台同款机器时）

```powershell
# 1) 手机：开发者选项 → 无线调试 → 配对码；电脑：
adb pair <ip>:<pairport> <6位码>
# 2) 关 Samsung「设置 → 安全与隐私 → 自动拦截程序」(否则 adb 写命令静默失败)
# 3) 一键恢复（脚本目录即仓库 scripts/）
powershell -File scripts\restore-flip5.ps1
powershell -File scripts\register-autostart.ps1
# 4) 手机侧 watcher 由 restore 脚本 push 并拉起；拔插外接屏验收两档切换
```

## 许可

脚本与 App 源码按 MIT 提供（见 `LICENSE`）。文档中的设备行为结论以实测固件为准，换固件/换机型需重新验证。
