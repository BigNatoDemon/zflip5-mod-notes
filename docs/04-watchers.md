# 04 双端 watcher 与自愈

## 分工

| | PC 端 `flip5-display-profile.ps1` | 手机端 `phone-watcher.sh` |
|---|---|---|
| 权限 | adb shell（经无线 adb） | 本机 shell（/data/local/tmp，setsid 后台） |
| 触发 | 3s 轮询 | 2s 轮询（快路径 1 个 settings 读） |
| 职责 | 插拔切档、不变量自愈、**交叉守护拉起手机端**、开机任务托管 | 插拔切档、不变量自愈、**电脑不在时独立工作** |
| 存活 | 计划任务 `Flip5DisplayProfile`（登录触发、隐藏、失败重试） | watchdog 外壳 + worker 双循环 |

两者动作**幂等**，同时跑不冲突。

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
| 手机端 watcher 全没 / 手机重启 | PC 交叉守护（adb 回连后 ≤ 一个轮询周期） |
| PC 睡眠/关机 | 手机端独立工作 |
| 手机重启 **且** PC 长睡 | **空窗**（无 root 没有 boot 时 shell 钩子；Shizuku 需每开机输配对码，评估后不采用）；PC 醒后自愈 |

## PC 端运维

```
powershell -File scripts\register-autostart.ps1        # 重建/启动计划任务（watcher 缺失时自动从同目录副本补）
Get-ScheduledTask Flip5DisplayProfile | % State
Unregister-ScheduledTask -TaskName Flip5DisplayProfile -Confirm:$false   # 撤销
# 重启实例加载新代码时：按命令行精确匹配旧 powershell 再杀（过滤串用拼接构造并排除 $PID，避免自杀）
```

日志：PC 端 `flip5-profile.log`（UTF-8），手机端 `/data/local/tmp/flip5-profile-phone.log`。
