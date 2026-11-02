package dev.zflip5.orienttile;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

/** 用设备内 adb 拉起手机端守护；前台服务形态（Samsung 不放行后台服务，开机自启也走这里） */
public class ReviveService extends Service {

    private static final String CHANNEL = "revive";
    private static final int NOTIFY_ID = 42;

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, final int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(new NotificationChannel(
                    CHANNEL, "拉起守护", NotificationManager.IMPORTANCE_MIN));
        }
        Notification n = new Notification.Builder(this, CHANNEL)
                .setContentTitle("正在拉起显示守护")
                .setSmallIcon(R.drawable.ic_fix)
                .build();
        startForeground(NOTIFY_ID, n);

        new Thread(new Runnable() {
            public void run() {
                String result = "(not run)";
                // 开机后 adbd 的无线端口未必已就绪（Wi-Fi 还没连上），最多试 8 次、每次间隔 15 秒
                for (int i = 1; i <= 8; i++) {
                    try {
                        Adb.ensureKey(ReviveService.this);
                        result = Adb.reviveWatcher(ReviveService.this);
                        if (result.contains("alive=2")) break;
                    } catch (Exception e) {
                        result = "EX " + e;
                    }
                    Log.i("OrientTile", "revive attempt " + i + " -> " + result);
                    try { Thread.sleep(15000); } catch (InterruptedException ignored) { break; }
                }
                Log.i("OrientTile", "revive result: " + result);
                stopForeground(true);
                stopSelf(startId);
            }
        }).start();
        return START_NOT_STICKY;
    }
}
