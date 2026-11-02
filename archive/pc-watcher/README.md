# PC 端 watcher（已退役，2026-11-02）

手机端 `scripts/phone-watcher.sh` 的 `ensure()` 已覆盖这里的全部职责（画布、密度、亮度、
ignore-orientation、外接屏旋转表、插拔切换），双跑只是重复，而且两端"方向事实源"不同会互相顶
（详见 `docs/04-watchers.md`）。它原本不可替代的唯一作用是"手机重启后靠 adb 回连把手机端 watcher 拉起来"，
这件事现在由 App 的设备内 adb 完成（`docs/08-self-adb.md`），所以电脑可以完全不参与。

- `flip5-display-profile.ps1` —— PC 端轮询 watcher（策略表与手机端等价，含交叉守护）
- `register-autostart.ps1` —— 注册登录计划任务（隐藏、单实例、失败重试）

想恢复：把两个文件复制回 `scripts/`，`powershell -NoProfile -ExecutionPolicy Bypass -File register-autostart.ps1`；
脚本内部写死了工作目录路径，挪位置要同步改。**注意与手机端 watcher 二选一**，别同时跑。
