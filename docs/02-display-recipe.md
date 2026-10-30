# 02 显示画布配方（镜像几何）

## 三条定律（实测，别再重新推导）

1. **镜像 = 单画布**：手机内屏与外接屏共用一套 logical canvas（`dumpsys display` 里两块屏的
   `logicalFrame` 恒等）。外接屏只是把这张画布克隆过去。
2. **`wm size` 只做等比 fit**：绝不各向异性拉伸，也不支持 `-d <display>`。
   画布比例与某块屏不一致时，那块屏居中加黑边。四组实测：
   `2560x1440→竖屏 1080x607 居中横条`、`2640x1080→横屏 441x1080 竖条`、
   `1440x3520→横屏满铺`、`1048x2560→横屏满铺`。
3. **override 按自然方向（竖屏）解释**：想要横屏 2560x1600 画布，必须写**竖屏形状** `wm size 1600x2560`；
   写横屏形状会在横屏下被换成竖条。

推论（零和）：画布比例只能贴合一块屏。本仓库定案 **S2 = 显示器永远 1:1**，手机吃黑边
（横屏左右各 456px、竖屏上下各 456px，面板 1080x2640 vs 画布 1600x2560 的几何差）。

## 密度 320dpi 是负载配置，勿 reset

`wm density 320`（= `Settings.Secure display_density_forced=320`）使
`sw = 画布宽px ÷ (320/160) = 800dp ≥ 600dp` 阈值 → 优酷/爱奇艺/红果等走**平板布局分支**，
且 screenLayout size class 为 `xlrg`。reset 回 480 → sw533dp + `lrg` → 掉回手机分支。

实测对照（画布 1600x2560）：

| 密度 | swdp | size class | 平板分支 | 安全画布宽下限 |
|---|---|---|---|---|
| 320 | 800 | xlrg | ✅ 双保险 | 1200px |
| 400 | 640 | lrg | ✅（仅 sw600 限定符） | 1500px |
| 480 | 533 | lrg | ❌ | — |

App 报"视口 800x1280"之类是 **dp 值**（像素 ÷ (dpi/160)），不是读取错误。

## 竖置显示器 + 横屏 EDID：外接屏独立扫描旋转

显示器物理竖放但 EDID 仍报横屏模式时，镜像画面是"躺"的。外接镜像屏是**独立 display**
（id 会变，从 `dumpsys display` 的 `type=EXTERNAL ... displayId=` 读），可单独设扫描旋转：

```
cmd window user-rotation -d <extId> lock N
```

联动表（手机方向 r → 外接旋转 e，合成恒定，实测 r=0/e=3 正立满屏）：

| r（user_rotation） | 0 竖 | 1 横 | 2 倒竖 | 3 倒横 |
|---|---|---|---|---|
| e | 3 | 2 | 1 | 0 |

几何底线：镜像画面跟随手机朝向。竖屏手机 + 竖置显示器 + 正确 e = 两边都满屏；
**横屏手机 + 竖置显示器 = 画面正立但上下大黑边**（竖面板装横图的必然），无解。

## 配套不变量（watcher 每轮核对）

- 接外接屏：`wm size <外接比例的竖屏形状>` + `set-ignore-orientation-request true` + 亮度 mode 0/值 1 + 外接旋转按表
- 拔外接屏：`wm size reset` + `set-ignore-orientation-request reset` + 亮度 mode 1
- `set-ignore-orientation-request` 是**内存态**（system_server 重启即丢），且没有它时竖屏锁定的 App 会把整屏钉回竖屏
- 密度 320 每轮核对（被 reset 会导致平板分支丢失）

## 验证命令

```
wm size; wm density
dumpsys display | grep -oE 'type=(INTERNAL|EXTERNAL), valid=true, isActive=true[^}]*'
cmd window get-ignore-orientation-request
cmd window user-rotation -d <extId>
# 视觉真相用截图（screencap 的 -d 要传 SurfaceFlinger 长 id，见 06-pitfalls）
```
