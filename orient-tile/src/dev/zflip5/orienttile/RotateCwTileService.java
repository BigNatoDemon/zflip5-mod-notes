package dev.zflip5.orienttile;

import android.graphics.drawable.Icon;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public class RotateCwTileService extends TileService {

    @Override
    public void onClick() {
        Rotate.step(getContentResolver(), +1);
        refresh();
    }

    @Override
    public void onStartListening() {
        refresh();
    }

    private void refresh() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setIcon(Icon.createWithResource(this, R.drawable.ic_cw));
        t.setLabel("顺时针转");
        t.setContentDescription("顺时针旋转屏幕，当前" + Rotate.label(Rotate.current(getContentResolver())));
        t.setState(Tile.STATE_ACTIVE);
        t.updateTile();
    }
}
