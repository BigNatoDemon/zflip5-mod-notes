---
name: android-display-override
description: Reason about and change Android display canvas, density and per-display rotation for mirrored/wired-external setups - wm size override semantics (portrait-shaped values, uniform fit only), dp math and the 600dp tablet-layout threshold, mirror single-canvas zero-sum geometry, per-display scan rotation for pivoted monitors, and letterbox/Size-Compat diagnosis. Use when a mirrored or external display shows bars, sideways or tiny UI, when an app reports odd viewport sizes, or when rotation locks misbehave.
---

# Android display override & mirror geometry

## wm size / wm density semantics

- `wm size WxH` sets a logical canvas interpreted in the display's **natural (portrait) orientation**.
  For a landscape canvas on a portrait panel write the **portrait-shaped pair** (e.g. monitor 2560x1600 → `wm size 1600x2560`);
  writing the landscape pair yields a narrow strip after rotation.
- Scaling is **uniform fit only**: aspect mismatch ⇒ centered bars on that display. No anisotropic stretch, no per-display flag
  (`wm size -d` unsupported on many builds; `cmd window size -d` exists but same uniform-fit rule).
- `wm size`/`wm density` overrides persist across reboot (display_settings.xml); `cmd window set-ignore-orientation-request`
  and per-display `cmd window user-rotation -d <id> lock N` are **in-memory** (lost on system_server restart).
- Density: app-visible dp = px ÷ (dpi/160). `display_density_forced` (=`wm density`) is a **load-bearing config** when apps
  gate tablet layouts: sw ≥ 600dp takes the tablet branch; e.g. canvas 1600px wide at 320dpi → sw800dp + size class `xlrg`,
  at 400dpi → sw640dp + `lrg` (some legacy code keys off `xlrg`), at 480dpi → sw533dp → phone branch.
  An app reporting "viewport 800x1280" is reporting dp, not a read error.

## Mirror (wired DP/HDMI mirroring) laws

- Mirror = **one shared logical canvas**; both displays show the same image, each uniform-fit into its own panel.
  Zero-sum: the canvas aspect can match only one screen; the other gets bars. Pick which screen is primary per orientation.
- Mirrored image orientation follows the **phone's** rotation. Therefore: portrait phone + landscape monitor ⇒ side bars on monitor;
  portrait phone + **physically pivoted** portrait monitor + correct per-display scan rotation ⇒ both full.
- Pivoted monitor with landscape EDID: fix with `cmd window user-rotation -d <extDisplayId> lock N`;
  the table by phone rotation r is `e = (K - r) mod 4` for a constant K (empirically K=3 for one pivot direction;
  verify r=0 visually then derive the rest). extDisplayId changes between sessions - parse from `dumpsys display`.
- Per-display rotation only rotates the image; it never re-lays-out content. It cannot make a landscape layout fill a portrait panel.

## Diagnosis

- Fill vs bars: compute from aspects, or screenshot; **viewport `logicalFrame/physicalFrame` being full does NOT mean the image fills**
  (mirror letterboxing is invisible in frames). `physicalFrame` smaller than panel = that display is the letterboxed one.
- App window shape: read the package-qualified window block in `dumpsys window windows`
  (`mBounds`, `mFullConfiguration` with swdp/dpi/orientation). A landscape-locked app on a portrait display shows as a
  **rotated 90° letterbox window** (Size-Compat); `ignore-orientation-request` and `FORCE_RESIZE_APP` do NOT remove it.
- Rotation state: `settings get system user_rotation` + `accelerometer_rotation`; `user_rotation` resets to 0 on reboot -
  persist intent in a `Settings.Secure` key and restore at daemon start.
