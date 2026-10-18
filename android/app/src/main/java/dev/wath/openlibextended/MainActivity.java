package dev.wath.openlibextended;

import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.view.MotionEvent;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private ReaderInactivityTimer readerTimer;
    private MethodChannel readerChannel;

    @SuppressWarnings("deprecation")
    private ReaderInactivityTimer timer() {
        if (readerTimer == null) {
            Handler handler = new Handler(Looper.getMainLooper());
            PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
            // Intentionally omit ON_AFTER_RELEASE: it would restart the phone's
            // two-minute timer after the ten-minute reader deadline.
            // No ACQUIRE_CAUSES_WAKEUP: the power button always remains usable.
            PowerManager.WakeLock lock = power.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK, "Openlib:ReaderInactivity");
            lock.setReferenceCounted(false);
            readerTimer = new ReaderInactivityTimer(SystemClock::uptimeMillis,
                new ReaderInactivityTimer.Scheduler() {
                    public void schedule(Runnable task, long delay) { handler.postDelayed(task, delay); }
                    public void cancel(Runnable task) { handler.removeCallbacks(task); }
                }, new ReaderInactivityTimer.DisplayLock() {
                    public void hold(long duration) { lock.acquire(duration); }
                    public void release() { if (lock.isHeld()) lock.release(); }
                });
        }
        return readerTimer;
    }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        readerChannel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
            "openlib/reader_screen_timeout");
        readerChannel.setMethodCallHandler((call, result) -> {
            if ("setReading".equals(call.method)) {
                timer().setReading(Boolean.TRUE.equals(call.arguments));
                result.success(null);
            } else result.notImplemented();
        });
    }
    @Override protected void onResume() {
        super.onResume();
        timer().setForeground(true);
        timer().setFocused(hasWindowFocus());
    }
    @Override protected void onPause() {
        timer().setForeground(false);
        super.onPause();
    }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        timer().setFocused(focused);
    }
    @Override public void onUserInteraction() {
        super.onUserInteraction();
        timer().interact();
    }
    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        // Native dispatch includes EPUB WebViews, dialogs and the image viewer.
        if (event.getActionMasked() != MotionEvent.ACTION_CANCEL) timer().interact();
        return super.dispatchTouchEvent(event);
    }
    @Override protected void onDestroy() {
        if (readerTimer != null) readerTimer.destroy();
        if (readerChannel != null) readerChannel.setMethodCallHandler(null);
        super.onDestroy();
    }
}
