# 04 watcher 与自愈（单层：只在手机上跑）

## 现状

常驻层只有手机端 `phone-watcher.sh`：本机 shell（`/data/local/tmp`，`setsid` 后台，2 秒快路径轮询）。
`ensure()` 每轮核对并补写画布 override、`ignore-orientation-request`、亮度、密度 320、外接扫描旋转（按表），
外加插拔切档与方向学习——这就是当初 PC 端 watcher 的全部职责。

PC 端 `flip5-display-profile.ps1` 与登录计划任务已于 2026-11-02 退役，脚本留在 `archive/pc-watcher/`。
理由：逻辑完全重复；且它每个写命令都要经过 adb，三星「自动拦截程序」一开就全部静默失效，而手机端走本机 shell 不受影响。
**两端并跑还会打架**（见下方"事实源不一致"）。

## 状态机（两端同构）

- 每轮读：外接屏是否存在及分辨率、内屏 orientation、`user_rotation`
- 插拔变化 → 应用对应档（见 02 文档不变量）
- 每轮/每 N 轮核对不变量并补写：画布 override、`ignore-orientation-request`、亮度、密度 320、外接扫描旋转（按表）
- 方向变化 → **只学习**：写 `Settings.Secure flip5_orient_mode`；启动时按它恢复（补 `user_rotation` 重启回 0 的洞）

## 为什么需要自愈

- `set-ignore-orientation-request` 与外接扫描旋转都是**内存态**：system_server 重启
  （Play 系统更新、整机重启）即清空；而插拔状态没变时主循环不会重放 → 必须每轮核对
- `user_rotation` 不持久（重启回 0）→ secure 键 + 启动恢复
- 拦截/清理类 App 可能杀进程 → watchdog + 交叉守护

## watchdog 与杀进程姿势（手机端）

```
setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &   # 必须 setsid，nohup 会被 adb 断开连带杀
pkill -f 'phone-watcher.sh worker'   # 只杀 worker（外壳 2 秒内重启它）
pkill -f 'phone-watche[r]'           # 全杀（括号 trick 避免匹配到自己）
pgrep -f 'phone-watche[r]'           # 判活；期望 2（外壳+worker）
```

**别用 `ps -A | grep`**：toybox 的 ps NAME 列只有 `sh`，不含脚本路径，永远空输出（曾据此误判进程已死）。

## 覆盖矩阵

| 故障 | 谁补 |
|---|---|
| worker 被杀 | 外壳 2s |
| 手机端 watcher 全没 / 手机重启 | **App 的 self-adb 链路自动拉起**（见 08），实测重启后 31 秒就位 |
| 电脑睡眠/关机/不在 | 手机端独立工作（实测断联期间拔插外屏两档都自动完成） |
| App 被卸载/强制停止、无线调试被关 | **空窗**：self-adb 连不上，需重连电脑跑一次 `restore-flip5.ps1` |

## 事实源不一致 = 双跑必打架（2026-11-02 实踩）

PC 版判方向读的是 `dumpsys display` 里**第一个 `type=INTERNAL, isActive=true` 的 viewport `orientation`**，
而 Flip5 有**两块 INTERNAL 屏**（外屏 FlexWindow 的 `installOrientation=1`，天然躺 90°）。合盖/外屏活动期它会
误判成横档、把外接锁成错的值；手机端按 `user_rotation` 要另一个值 → 两边几秒内互相顶（日志里 `2 -> 3 -> 2` 就是铁证）。
**方向的事实源只能是 `user_rotation`**，手机版已改成这样。

## 运维

```
pgrep -f 'phone-watche[r]'                       # 判活，期望 2（外壳+worker）
pkill -f 'phone-watche[r]'                        # 全杀（括号 trick 防自匹配）
setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &   # 手动拉起
tail /data/local/tmp/flip5-profile-phone.log      # 决策日志
```

日志：手机端 `/data/local/tmp/flip5-profile-phone.log`；PC 端历史日志在 `archive/pc-watcher/`。
