# 05 刷机 / 恢复出厂后的一键恢复

## 前置（人工，无法自动化）

1. **FRP**：任何清数据的刷机/恢复出厂都会在开机向导要求**之前同步过的 Google/三星账号**。
   没有凭据 = 砖，无 adb 旁路。动手先确认账号可用。
2. **关 Auto Blocker**（设置 → 安全与隐私 → 自动拦截程序），否则后续所有 adb 写命令静默失败。
3. 无线调试配对一次（见 01）。

## 一键恢复

```powershell
powershell -File scripts\restore-flip5.ps1          # -DryRun 预览；-SkipPackages 跳过禁用预装
powershell -File scripts\register-autostart.ps1     # 开机任务 + 启动 PC watcher
```

`restore-flip5.ps1` 依次：等设备 → 核对固件白名单 → 装 Aerial/SmartTube → 装磁贴+授权+上屏 →
设 HOME 角色 → 禁用预装清单 → 写 settings（含密度 320、方向默认键）→ 按外接屏分辨率设画布 →
push 并 setsid 拉起手机端 watcher → 回读校验打印。脚本**幂等**，重跑无副作用。

已知例外：个别包在当前固件受保护，shell 禁用会抛 SecurityException（脚本容忍并标注），
需要禁用只能走设置界面手动。

## Odin 红线

- 五件套里 **CSC 与手机区域不一致时绝不刷 CSC 槽**（换区域 + 清数据）；只刷 BL/AP/CP
- bootloader 锁死机型：刷任何修补过的 AP 都会 `secure check fail : init_boot()`；
  降级被反回滚熔丝挡（`SW REV CHECK FAIL`）。**可刷集合 ∩ 可解锁集合 = 空**，root 路线已证死

## 存活性矩阵（决定哪些必须每次重做）

| 项 | 手机重启 | 刷机/恢复出厂 |
|---|---|---|
| `wm size` override、密度 override | ✅ | ❌（restore/watcher 补） |
| settings（亮度/show_taps/force_resizable/accel） | ✅ | ❌ |
| `user_rotation` | ❌ 回 0（watcher 按 secure 键恢复） | ❌ |
| `ignore-orientation-request`、外接扫描旋转 | ❌ 内存态（watcher 每轮补） | ❌ |
| 已装 App / HOME 角色 / 禁用状态 / 磁贴位置 | ✅ | ❌（restore 补） |
| 无线调试配对 | ✅ 自动回连 | ❌ 重新 pair |
| 手机端 watcher 进程 | ❌（PC 交叉守护补） | ❌（restore 补） |
| PC 计划任务 | — | —（PC 侧持久） |

## 验收清单

- 拔插外接屏各一次：日志出现"拔出→还原"/"接入→画布 …"两行，间隔 ≤ 一个轮询周期
- `wm size` / `wm density` / 两块屏 viewport / 外接旋转 / `flip5_orient_mode` 与预期一致
- 磁贴点四下：`user_rotation` 0→1→2→3 循环，外接旋转按表联动，显示器画面始终正立
