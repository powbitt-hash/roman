package sk.bubnovavyprava.app;

import android.Manifest;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AcousticEchoCanceler;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.HashMap;

// Surový mikrofón: AudioRecord so zdrojom UNPROCESSED (ak ho tablet má), inak VOICE_RECOGNITION,
// vždy bez automatického zosilnenia a potláčania šumu. Zvuk ide po 20 ms do WebView, nikam sa neukladá.
// Ukladanie súborov (fileOpen/fileWrite/fileClose) slúži len na nahrávku hry, ktorú si používateľ sám zapne.
@CapacitorPlugin(name = "RawMic")
public class RawMicPlugin extends Plugin {
    private AudioRecord rec;
    private Thread th;
    private volatile boolean run;
    private final HashMap<Integer, OutputStream> files = new HashMap<>();
    private final HashMap<Integer, String> paths = new HashMap<>();
    private int nextId = 1;

    @PluginMethod
    public void start(PluginCall call) {
        if (getContext().checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { call.reject("permission"); return; }
        stopRec();
        int sr = call.getInt("sr", 48000);
        AudioManager am = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        boolean un = Build.VERSION.SDK_INT >= 24 && "true".equals(am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED));
        String want = call.getString("source", "auto");
        java.util.ArrayList<String> order = new java.util.ArrayList<>();
        if (!"auto".equals(want)) order.add(want);
        if (un) order.add("unprocessed");
        order.add("voice_recognition");
        order.add("mic");
        int min = AudioRecord.getMinBufferSize(sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        String used = null;
        for (String nm : order) {
            int src = srcId(nm);
            if (src < 0) continue;
            try {
                AudioRecord a = new AudioRecord(src, sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(min, sr / 5));
                if (a.getState() == AudioRecord.STATE_INITIALIZED) { rec = a; used = nm; break; }
                a.release();
            } catch (Exception ignored) {}
        }
        if (rec == null) { call.reject("init"); return; }
        int sid = rec.getAudioSessionId();
        try { if (AutomaticGainControl.isAvailable()) { AutomaticGainControl x = AutomaticGainControl.create(sid); if (x != null) x.setEnabled(false); } } catch (Exception ignored) {}
        try { if (NoiseSuppressor.isAvailable()) { NoiseSuppressor x = NoiseSuppressor.create(sid); if (x != null) x.setEnabled(false); } } catch (Exception ignored) {}
        try { if (AcousticEchoCanceler.isAvailable()) { AcousticEchoCanceler x = AcousticEchoCanceler.create(sid); if (x != null) x.setEnabled(false); } } catch (Exception ignored) {}
        rec.startRecording();
        run = true;
        final AudioRecord r = rec;
        final int N = sr / 50;
        th = new Thread(() -> {
            short[] b = new short[N];
            byte[] by = new byte[N * 2];
            long pos = 0;
            while (run) {
                int n = r.read(b, 0, N);
                if (n <= 0) { if (n < 0) break; continue; }
                for (int i = 0; i < n; i++) { by[2 * i] = (byte) (b[i] & 0xff); by[2 * i + 1] = (byte) ((b[i] >> 8) & 0xff); }
                JSObject o = new JSObject();
                o.put("pos", pos);
                o.put("n", n);
                o.put("d", Base64.encodeToString(by, 0, n * 2, Base64.NO_WRAP));
                notifyListeners("pcm", o);
                pos += n;
            }
        }, "RawMic");
        th.setPriority(Thread.MAX_PRIORITY);
        th.start();
        JSObject res = new JSObject();
        res.put("src", used);
        res.put("sr", rec.getSampleRate());
        call.resolve(res);
    }

    private static int srcId(String nm) {
        switch (nm) {
            case "voice_performance": return Build.VERSION.SDK_INT >= 29 ? MediaRecorder.AudioSource.VOICE_PERFORMANCE : -1;
            case "unprocessed": return Build.VERSION.SDK_INT >= 24 ? MediaRecorder.AudioSource.UNPROCESSED : -1;
            case "voice_recognition": return MediaRecorder.AudioSource.VOICE_RECOGNITION;
            case "camcorder": return MediaRecorder.AudioSource.CAMCORDER;
            case "mic": return MediaRecorder.AudioSource.MIC;
            default: return -1;
        }
    }

    private void stopRec() {
        run = false;
        if (th != null) { try { th.join(300); } catch (InterruptedException ignored) {} th = null; }
        if (rec != null) { try { rec.stop(); } catch (Exception ignored) {} rec.release(); rec = null; }
    }

    @PluginMethod
    public void stop(PluginCall call) { stopRec(); call.resolve(); }

    @Override
    protected void handleOnDestroy() { stopRec(); }

    @PluginMethod
    public void fileOpen(PluginCall call) {
        String name = call.getString("name", "nahravka.bin");
        String mime = call.getString("mime", "application/octet-stream");
        try {
            OutputStream os; String path;
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues v = new ContentValues();
                v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                v.put(MediaStore.Downloads.MIME_TYPE, mime);
                v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/BubnovaVyprava");
                Uri u = getContext().getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                if (u == null) { call.reject("insert"); return; }
                os = getContext().getContentResolver().openOutputStream(u);
                path = "Stiahnuté súbory/BubnovaVyprava/" + name;
            } else {
                File dir = getContext().getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                File f = new File(dir, name);
                os = new FileOutputStream(f);
                path = f.getAbsolutePath();
            }
            int id = nextId++;
            files.put(id, os); paths.put(id, path);
            JSObject r = new JSObject(); r.put("id", id); r.put("path", path); call.resolve(r);
        } catch (Exception e) { call.reject("open: " + e.getMessage()); }
    }

    @PluginMethod
    public void fileWrite(PluginCall call) {
        OutputStream os = files.get(call.getInt("id", -1));
        if (os == null) { call.reject("id"); return; }
        try { os.write(Base64.decode(call.getString("d", ""), Base64.DEFAULT)); call.resolve(); } catch (Exception e) { call.reject("write: " + e.getMessage()); }
    }

    @PluginMethod
    public void fileClose(PluginCall call) {
        int id = call.getInt("id", -1);
        OutputStream os = files.remove(id);
        String p = paths.remove(id);
        try { if (os != null) os.close(); JSObject r = new JSObject(); r.put("path", p); call.resolve(r); } catch (Exception e) { call.reject("close: " + e.getMessage()); }
    }
}
