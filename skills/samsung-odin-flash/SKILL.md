---
name: samsung-odin-flash
description: Flash Samsung firmware with Odin safely - choose the right files (BL/AP/CP/CSC vs HOME_CSC), match region/CSC and anti-rollback bit, judge bootloader-unlock feasibility (OEM toggle presence, One UI 8+ removal, KG states), and interpret secure-check failures on locked bootloaders. Use when the user downloads firmware from samfw/sammobile, asks which file to flash, wants to root/downgrade a Samsung device, or a flash/reflash goes wrong.
---

# Samsung Odin flashing

## File set (five pieces)

- `BL_` bootloader, `AP_` system+boot+init_boot (the big one), `CP_` modem, `CSC_` (wipe + region config), `HOME_CSC_` (keep data).
- Flash BL/AP/CP always; **CSC slot only when you intend to change region and wipe**. Same model number can cover several
  regions (e.g. SM-F7310 = CN/HK/TW) and cross-flashes fine, but a mismatched CSC rewrites region config.
- Verify against the device: `ro.build.version.incremental` should equal the firmware string; `ro.oem.key1` = region/CSC.
- samfw pages list per-partition files with sizes; the "Full Files" bundle = all five. MD5 on the page is for the bundle.

## Anti-rollback & downgrade

- The digit after the CSC code in the version string is the **bit/SW rev** (e.g. `...ZSU9...` = bit 9). You may flash equal or higher bit;
  lower bit fails (`SW REV CHECK FAIL`) because of the rollback fuse - read current bit from Download mode (`SPU:x, AR:n`) or the version string.
- Downgrading to escape a policy change (e.g. to regain bootloader unlock) usually dies here: if the unlock-capable builds are below
  the fused bit, the intersection of flashable and unlockable is empty.

## Bootloader unlock feasibility checklist (do before promising root)

1. Developer options → is there an **OEM unlock** entry at all? On One UI 8+ Samsung removed the capability in firmware
   (entry absent, `am start` of the OemUnlock activity = Activity not found). Absent entry = dead end, KG unrelated.
2. Download mode lines: `KG STATUS` (`CHECKING` = not blocking; `PRENORMAL/LOCKED` = blocking), `SECURE DOWNLOAD ENABLE`
   (blocks third-party recovery), `WARRANTY VOID 0x0` (fuse not blown), `OEM lock` line missing = unlock menu removed.
3. Unlocking (where possible) blows the Knox eFuse permanently: warranty, Samsung Pay, Secure Folder gone; full wipe; some foldables
   historically lost camera after unlock on non-EU CSC.
4. On a **locked** bootloader, flashing a Magisk-patched AP fails at boot verification: `secure check fail : init_boot()` -
   the write is rejected/verification fails regardless of OS version. Not fixable from software.
5. Root target on Android 13+ is **init_boot**, not boot; Magisk version must support the device's API level
   (check release notes; old Magisk fails on new sepolicy/Zygisk formats).

## Post-flash expectations

- Wireless-debugging pairing and all settings are wiped ⇒ re-pair adb; re-apply device profile from your restore package.
- Odin needs the Samsung USB driver; Download mode enumerates as a COM port (`SAMSUNG Mobile USB Modem`);
  avoid USB hubs during flash; keep only `Auto Reboot` + `F. Reset Time` checked.
- Firmware bit/region facts to record after flashing: incremental, `ro.oem.key1`, `ro.boot.warranty_bit`, SDK level.
