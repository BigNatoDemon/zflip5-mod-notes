package dev.zflip5.orienttile;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** 开机后拉起守护（Samsung 要求前台服务，不能是后台 service） */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent intent) {
        Log.i("OrientTile", "boot -> ReviveService");
        Intent i = new Intent(c, ReviveService.class);
        try {
            c.startForegroundService(i);
        } catch (Exception e) {
            Log.e("OrientTile", "startForegroundService failed", e);
        }
    }
}
