---
name: ble-hid-remote-diagnose
description: Diagnose Bluetooth HID (HOGP) remotes and keyboards that pair once but then fail to reconnect - capture the connect attempt, distinguish key-mismatch from silence, and apply the resolvable-private-address vs legacy-pairing model. Use when a BLE remote/keyboard shows as paired but "tap does nothing", demands re-pairing, or works on a TV box but not on a phone.
---

# BLE HID remote reconnect diagnosis

## Capture

1. `pidof com.android.bluetooth`; clear logcat; have the user tap the paired entry (shell `click-tile`-style triggers may not
   dispatch on all OEMs - a real tap always does).
2. Filter by the bluetooth pid plus tags `btif_hh`, `bta_hh`, `HidHostService`, `smp`, `bt_btm`; truncate lines.

## Read the signature

- **Healthy**: `btif_hh_connect` → `BTA_HH_OPEN` / HOGP state 2 within ~2s.
- **The classic failure**: `connectEnabledProfile(HidHostService)` → `bta_hh_connect_upgrade: Upgrading to direct connection`
  → state 0→1 → **exactly ~10s of silence (zero advertisements from the remote)** → `HidHostService msg.what=30` → state 1→0.
  **No SMP/pairing-failure lines at all** ⇒ not a key mismatch; the remote never answered at link layer.
- Bond facts: `dumpsys bluetooth_manager` → `Bonded devices` line (`le_linkkey_known:T`, `SecureConn:F` = LE Legacy)
  and `shim::record ... sm4:/SecureConn:` lines; `connection_counter` tells how often it ever connected.

## Model (why it happens)

- Phones rotate their LE identity address (RPA) every ~7-15 min (`le_address_manager: Scheduling address rotation`).
- LE **Legacy** pairing often exchanges no IRK; a cheap remote then only sends **directed** wake advertisements to the address it
  bonded with. After rotation those packets address a stale RPA ⇒ the phone never sees the remote ⇒ 10s timeout.
- TV boxes/hosts with **static** LE addresses keep working ⇒ "fine on the TV, broken on the phone".
- Testable prediction: reconnect works within one rotation window after pairing, fails across it.

## Remedies (phone side has no fix - RPA rotation is a privacy feature, no knob without root)

1. Press the remote's **broadcast/pairing combo** (common: Home+Menu or OK+Back, 3-5s) while tapping connect - undirected ads land.
2. USB dongle remote (USB HID, address-independent) - best for media-box builds.
3. Replace with an LE **Secure Connections** remote (IRK exchanged ⇒ resolves rotated addresses).
4. Do not "fix" by deleting/re-pairing every time: it only works because pairing uses undirected discovery.

## Reporting

Give the timeline (click → connect → timeout), the bond facts, the model verdict, and the chosen remedy.
Never claim key mismatch without SMP evidence; silence ≠ rejection.
