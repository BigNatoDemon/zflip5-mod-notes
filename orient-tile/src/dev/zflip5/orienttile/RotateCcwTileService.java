package dev.zflip5.orienttile;

import android.graphics.drawable.Icon;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public class RotateCcwTileService extends TileService {

    @Override
    public void onClick() {
        Rotate.step(getContentResolver(), -1);
        refresh();
    }

    @Override
    public void onStartListening() {
        refresh();
    }

    private void refresh() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setIcon(Icon.createWithResource(this, R.drawable.ic_ccw));
        t.setLabel("逆时针转");
        t.setContentDescription("逆时针旋转屏幕，当前" + Rotate.label(Rotate.current(getContentResolver())));
        t.setState(Tile.STATE_ACTIVE);
        t.updateTile();
    }
}
