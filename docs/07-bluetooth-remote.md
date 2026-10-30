# 07 蓝牙遥控"第二次连接要重新配对"

## 症状

配对列表里有设备（bond 记录在、`le_linkkey_known:T`），点它**没反应**；删除重新配对才能用。
电视盒子/魔盒端同一遥控一切正常。

## 抓包结论（按蓝牙进程 PID 过滤 logcat）

```
onDevicePreferenceClick            ← 用户点了它
BluetoothDevice.connect()
btif_hh_connect: <addr>[public][BT_TRANSPORT_LE]
bta_hh_connect_upgrade: Upgrading to direct connection
HID state 0 -> 1 (CONNECTING)
……10 秒内零条来自遥控的广播/链路事件……
HidHostService msg.what=30          ← 10s 超时
HID state 1 -> 0 (DISCONNECTED)
```

**没有任何 SMP/配对失败日志** → 不是键不匹配；是链路层等不到遥控应答。

## 机制模型

- 手机 LE 地址是 **RPA，约 7-14 分钟轮换**（`le_address_manager: Scheduling address rotation`）
- 该类遥控是 **LE Legacy 配对**（`SecureConn:F`），不交换/不解析 IRK；
  唤醒后只朝"配对那一刻记住的地址"发定向广播
- 手机地址一轮换，遥控永远喊不到人；而手机的直连又需要遥控先广播 → 死锁
- 重新配对走通用发现（与地址无关）所以总能成功；配好后一个轮换周期内重连正常 →
  可验证预测：**重配后 ~14 分钟内重连成功，跨周期必失败**
- 电视盒子/魔盒通常用**固定 LE 地址** → 定向广播永远命中 → 那边正常

## 缓解（手机侧无解：关 RPA 需 root/厂商属性）

1. 点连接的同时长按遥控的**广播态组合键**（天猫系常见：主页+菜单 / OK+返回 3-5 秒），
   让它发非定向广播，10 秒内可连上
2. 换 **USB 接收器**遥控（走 USB HID，与 BLE 地址无关）——对大屏方案也是最稳的
3. 换支持 LE Secure Connections 的遥控（交换 IRK，能解析轮换地址）

## 排查方法备忘

- 先 `pidof com.android.bluetooth`，按 PID 过滤；关键 tag：`btif_hh`、`bta_hh`、`HidHostService`
  （`msg.what=30` = 10s 超时）、`le_address_manager`（地址轮换）
- bond 记录看 `dumpsys bluetooth_manager` 的 `Bonded devices` 段与 `shim::record` 行
  （`le_linkkey_known` / `SecureConn` / 地址类型）
- 过滤串里别出现 `logcat` 字样，否则抓包进程会把自己杀掉
