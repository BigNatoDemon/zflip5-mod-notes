package dev.zflip5.orienttile;

import android.graphics.drawable.Icon;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

/**
 * 一键修复：写触发文件，shell 身份的手机端 watcher 读到后无条件重放整套显示配置，
 * 处理完把这个文件删掉 —— "文件还在"就是守护没干活的唯一可靠信号。
 *
 * 为什么不用 Settings：这台固件对 App 读写自定义键一律拒绝（写抛
 * "You cannot keep your settings in the secure settings."，targetSdk 降到 28 同样拦；
 * 读则静默返回默认值）。为什么不用 shell 写文件给 App 读：Android 11+ 下 App 看不见
 * 别的 uid（含 shell）在它自己 Android/data 目录里建的文件，chmod 666 也没用。
 */
public class FixTileService extends TileService {

    private static final String FIX = "fix";

    @Override
    public void onClick() {
        try {
            File f = new File(dir(), FIX);
            FileOutputStream out = new FileOutputStream(f);
            out.write(Long.toString(System.currentTimeMillis()).getBytes());
            out.close();
            android.util.Log.i("OrientTile", "fix trigger -> " + f.getAbsolutePath());
            watchConsumed(f);
        } catch (IOException | NullPointerException e) {
            android.util.Log.e("OrientTile", "fix trigger write failed", e);
        }
        refresh();
    }

    /** 触发文件 4 秒后还在 = 守护没在跑，用设备内 adb 把它拉起来再等一轮 */
    private void watchConsumed(final File f) {
        new Thread(new Runnable() {
            public void run() {
                try { Thread.sleep(4000); } catch (InterruptedException ignored) {}
                if (!f.isFile()) return;
                android.util.Log.i("OrientTile", "trigger not consumed -> revive via device-local adb");
                Adb.reviveWatcher(FixTileService.this);
                try { Thread.sleep(3000); } catch (InterruptedException ignored) {}
                android.util.Log.i("OrientTile", "after revive, pending=" + f.isFile());
            }
        }).start();
    }

    @Override
    public void onStartListening() {
        refresh();
    }

    private File dir() {
        File d = getExternalFilesDir(null);
        if (d != null && !d.isDirectory()) d.mkdirs();   // 目录只能由 App 自己建
        return d;
    }

    private void refresh() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setIcon(Icon.createWithResource(this, R.drawable.ic_fix));
        t.setLabel("修复画面");
        boolean pending = false;
        try {
            File d = dir();
            pending = d != null && new File(d, FIX).isFile();
        } catch (Exception e) {
            android.util.Log.e("OrientTile", "pending check failed", e);
        }
        android.util.Log.i("OrientTile", "pending=" + pending);
        // 永远保持可点：STATE_UNAVAILABLE 的磁贴会被 One UI 吞掉点击，等于自己把自己锁死
        t.setState(Tile.STATE_ACTIVE);
        t.setContentDescription(pending
                ? "上次的修复请求还没被处理：手机端守护可能已停，需连电脑拉起"
                : "守护在线，点一下重放整套显示配置（画布/密度/旋转/亮度）");
        t.updateTile();
    }
}
