package dev.zflip5.orienttile;

import android.content.ContentResolver;
import android.provider.Settings;

public final class Rotate {

    public static int current(ContentResolver cr) {
        int u = Settings.System.getInt(cr, Settings.System.USER_ROTATION, 0);
        return (u >= 0 && u <= 3) ? u : 0;
    }

    /** 步进 ±1（模 4），并永久关闭传感器旋转 */
    public static void step(ContentResolver cr, int delta) {
        int next = ((current(cr) + delta) % 4 + 4) % 4;
        Settings.System.putInt(cr, Settings.System.ACCELEROMETER_ROTATION, 0);
        Settings.System.putInt(cr, Settings.System.USER_ROTATION, next);
        android.util.Log.i("OrientTile", "step " + delta + " -> user_rotation=" + next);
    }

    public static String label(int m) {
        switch (m) {
            case 1: return "横";
            case 2: return "倒竖";
            case 3: return "倒横";
            default: return "竖";
        }
    }
}
