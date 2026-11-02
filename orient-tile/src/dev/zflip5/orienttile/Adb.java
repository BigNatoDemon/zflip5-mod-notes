package dev.zflip5.orienttile;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * 设备内 adb 客户端：APK 自带 arm64 的 adb 可执行文件与它的共享库（jni/ -> nativeLibraryDir），
 * 连的是本机无线调试监听的回环端口，拿到的是 shell uid。
 *
 * 钥匙与端口都必须由本 App 自己创建：Android 11+ 下 App 看不见别的 uid（含 shell）
 * 在它 Android/data 目录里放的文件，所以 adb push 进去的 key 它读不到。
 *  - HOME/.android/adbkey：首次由 `adb keygen` 生成，之后需人工配对一次
 *    （手机：开发者选项→无线调试→使用配对码配对设备；然后 `adb pair 127.0.0.1:<配对端口> <码>`）
 *  - HOME/adbport：NSD 查 _adb-tls-connect._tcp 得到；端口每次重开无线调试/重启都会变
 */
public final class Adb {

    private static final String TAG = "OrientTile";
    private static final String SVC_TYPE = "_adb-tls-connect._tcp";

    private static File home(Context c) {
        File d = c.getExternalFilesDir(null);
        if (d != null && !d.isDirectory()) d.mkdirs();
        return d;
    }

    private static String bin(Context c) {
        return new File(c.getApplicationInfo().nativeLibraryDir, "libadbexec.so").getAbsolutePath();
    }

    /** 执行一次 adb，返回合并后的输出；8 秒超时则杀进程 */
    public static synchronized String run(Context c, String... args) {
        ArrayList<String> cmd = new ArrayList<>();
        cmd.add(bin(c));
        for (String a : args) cmd.add(a);
        final StringBuilder out = new StringBuilder();
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.environment().put("HOME", home(c).getAbsolutePath());
            pb.environment().put("LD_LIBRARY_PATH", c.getApplicationInfo().nativeLibraryDir);
            pb.redirectErrorStream(true);
            final Process p = pb.start();
            Thread reader = new Thread(new Runnable() {
                public void run() {
                    BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                    String line;
                    try { while ((line = r.readLine()) != null) out.append(line).append('\n'); } catch (Exception ignored) {}
                }
            });
            reader.start();
            p.waitFor(8, TimeUnit.SECONDS);
            p.destroy();
            reader.join(500);
        } catch (Exception e) {
            Log.e(TAG, "adb run failed", e);
            out.append("ERR ").append(e);
        }
        return out.toString().trim();
    }

    private static File keyFile(Context c) { return new File(home(c), ".android/adbkey"); }

    /** 首把钥匙由 App 自己生成（这样它才读得到） */
    public static boolean ensureKey(Context c) {
        File k = keyFile(c);
        if (k.isFile()) return true;
        k.getParentFile().mkdirs();
        String out = run(c, "keygen", k.getAbsolutePath());
        Log.i(TAG, "keygen: " + out);
        return k.isFile();
    }

    public static String publicKey(Context c) {
        File pub = new File(keyFile(c).getAbsolutePath() + ".pub");
        if (!pub.isFile()) return "(no pub key yet)";
        try {
            byte[] buf = new byte[(int) pub.length()];
            FileInputStream in = new FileInputStream(pub);
            in.read(buf);
            in.close();
            return new String(buf);
        } catch (Exception e) { return "ERR " + e; }
    }

    /** NSD 找无线调试连接端口，最多等 timeoutMs；找到就缓存进 HOME/adbport */
    public static int discoverPort(final Context c, long timeoutMs) {
        final int[] found = {0};
        final CountDownLatch latch = new CountDownLatch(1);
        try {
            final NsdManager nsd = (NsdManager) c.getSystemService(Context.NSD_SERVICE);
            NsdManager.DiscoveryListener dl = new NsdManager.DiscoveryListener() {
                public void onDiscoveryStarted(String t) {}
                public void onServiceFound(NsdServiceInfo info) {
                    if (info.getServiceType() == null || !info.getServiceType().startsWith("_adb-tls-connect")) return;
                    nsd.resolveService(info, new NsdManager.ResolveListener() {
                        public void onResolveFailed(NsdServiceInfo i, int errorCode) {}
                        public void onServiceResolved(NsdServiceInfo i) {
                            found[0] = i.getPort();
                            latch.countDown();
                        }
                    });
                }
                public void onServiceLost(NsdServiceInfo i) {}
                public void onDiscoveryStopped(String t) {}
                public void onStartDiscoveryFailed(String t, int e) { latch.countDown(); }
                public void onStopDiscoveryFailed(String t, int e) {}
            };
            nsd.discoverServices(SVC_TYPE, NsdManager.PROTOCOL_DNS_SD, dl);
            latch.await(timeoutMs, TimeUnit.MILLISECONDS);
            stop(nsd, dl);
        } catch (Exception e) {
            Log.e(TAG, "nsd failed", e);
        }
        if (found[0] > 0) writePort(c, found[0]);
        return found[0];
    }

    /** android-34 的 NsdManager stub 里没有 stopDiscovery（运行时存在），只能反射调 */
    private static void stop(NsdManager nsd, NsdManager.DiscoveryListener l) {
        try {
            NsdManager.class.getMethod("stopDiscovery", NsdManager.DiscoveryListener.class).invoke(nsd, l);
        } catch (Throwable t) {
            Log.i(TAG, "stopDiscovery unavailable: " + t);
        }
    }

    private static void writePort(Context c, int port) {
        try {
            FileOutputStream out = new FileOutputStream(new File(home(c), "adbport"));
            out.write(Integer.toString(port).getBytes());
            out.close();
        } catch (Exception ignored) {}
    }

    private static int cachedPort(Context c) {
        try {
            File f = new File(home(c), "adbport");
            byte[] buf = new byte[16];
            FileInputStream in = new FileInputStream(f);
            int n = in.read(buf);
            in.close();
            String s = new String(buf, 0, n).trim();
            return s.matches("\\d+") ? Integer.parseInt(s) : 0;
        } catch (Exception e) { return 0; }
    }

    /** 拉起手机端守护 */
    public static String reviveWatcher(Context c) {
        if (!ensureKey(c)) return "keygen failed";
        int port = discoverPort(c, 6000);
        if (port == 0) port = cachedPort(c);
        if (port == 0) return "port not found (NSD)";
        String serial = "127.0.0.1:" + port;
        String conn = run(c, "connect", serial);
        String out = run(c, "-s", serial, "shell",
                "setsid sh /data/local/tmp/phone-watcher.sh >/dev/null 2>&1 < /dev/null &");
        String alive = run(c, "-s", serial, "shell", "pgrep -f 'phone-watche[r]' | wc -l").trim();
        Log.i(TAG, "revive port=" + port + " connect=" + conn + " out=" + out + " alive=" + alive);
        return "port=" + port + " connect[" + conn + "] shell[" + out + "] alive=" + alive;
    }
}
