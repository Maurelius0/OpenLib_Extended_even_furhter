package dev.wath.openlibextended;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.CancellationSignal;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowInsetsAnimationController;
import android.view.WindowInsetsAnimationControlListener;
import android.view.animation.LinearInterpolator;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private ReaderInactivityTimer readerTimer;
    private MethodChannel readerChannel;
    private MethodChannel readerSystemBarsChannel;
    private boolean readerActive = false;
    private boolean readerControlsVisible = false;
    // Shared with the Flutter reader controls. Android 11+ controls the real
    // system bar's alpha; older Android uses its platform-managed transition.
    private static final long READER_FADE_MS = 150L;
    private int statusBarAnimationGeneration = 0;
    private ValueAnimator statusBarAnimator;
    private CancellationSignal statusBarCancellation;

    private void cancelStatusBarAnimation() {
        statusBarAnimationGeneration++;
        if (statusBarAnimator != null) {
            ValueAnimator old = statusBarAnimator;
            statusBarAnimator = null;
            old.cancel();
        }
        if (statusBarCancellation != null) {
            CancellationSignal old = statusBarCancellation;
            statusBarCancellation = null;
            old.cancel();
        }
    }

    // Android 11+ lets us fade the *real* status bar in approximately the
    // same 150 ms as Flutter's reader menu, without touching the navigation bar.
    // Requests can be denied or cancelled (e.g. loss of window focus), in
    // which case fall back to the working immediate visibility commands.
    private void animateReaderStatusBar() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R
                || !ValueAnimator.areAnimatorsEnabled()
                || !hasWindowFocus()) {
            cancelStatusBarAnimation();
            updateReaderStatusBar();
            return;
        }
        WindowInsetsController systemBars = getWindow().getInsetsController();
        if (systemBars == null) {
            cancelStatusBarAnimation();
            updateReaderStatusBar();
            return;
        }

        cancelStatusBarAnimation();
        final int request = statusBarAnimationGeneration;
        final boolean show = readerControlsVisible;
        final CancellationSignal signal = new CancellationSignal();
        statusBarCancellation = signal;
        systemBars.controlWindowInsetsAnimation(
                WindowInsets.Type.statusBars(), READER_FADE_MS,
                new LinearInterpolator(), signal,
                new WindowInsetsAnimationControlListener() {
                    @Override public void onReady(
                            WindowInsetsAnimationController control, int types) {
                        if (request != statusBarAnimationGeneration || !readerActive) {
                            if (control.isReady()) {
                                control.finish(!readerActive || readerControlsVisible);
                            }
                            return;
                        }
                        if ((types & WindowInsets.Type.statusBars()) == 0) {
                            control.finish(show);
                            return;
                        }

                        // Hold the bar in place and animate transparency, rather
                        // than slide it down into the page. The reader already
                        // reserves its full-height safe area.
                        final ValueAnimator fade = ValueAnimator.ofFloat(
                                show ? 0f : 1f, show ? 1f : 0f);
                        fade.setDuration(READER_FADE_MS);
                        fade.setInterpolator(new LinearInterpolator());
                        fade.addUpdateListener(animation -> {
                            if (request != statusBarAnimationGeneration
                                    || !control.isReady()) return;
                            float alpha = (Float) animation.getAnimatedValue();
                            control.setInsetsAndAlpha(
                                    control.getShownStateInsets(), alpha, alpha);
                        });
                        fade.addListener(new AnimatorListenerAdapter() {
                            private boolean cancelled;
                            @Override public void onAnimationCancel(Animator animation) {
                                cancelled = true;
                            }
                            @Override public void onAnimationEnd(Animator animation) {
                                if (request == statusBarAnimationGeneration) {
                                    statusBarAnimator = null;
                                    statusBarCancellation = null;
                                    if (!cancelled && control.isReady()) control.finish(show);
                                }
                            }
                        });
                        statusBarAnimator = fade;
                        fade.start();
                    }
                    @Override public void onFinished(
                            WindowInsetsAnimationController control) {
                        if (request == statusBarAnimationGeneration) {
                            statusBarAnimator = null;
                            statusBarCancellation = null;
                        }
                    }
                    @Override public void onCancelled(
                            WindowInsetsAnimationController control) {
                        if (request == statusBarAnimationGeneration) {
                            statusBarAnimator = null;
                            statusBarCancellation = null;
                            updateReaderStatusBar();
                        }
                    }
                });
    }

    // Hide only the status bar. Keep the system navigation bar fully functional.
    // WindowInsetsController works with mandatory edge-to-edge on modern Android.
    @SuppressWarnings("deprecation")
    private void updateReaderStatusBar() {
        final boolean showStatusBar = !readerActive || readerControlsVisible;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                if (showStatusBar) controller.show(WindowInsets.Type.statusBars());
                else controller.hide(WindowInsets.Type.statusBars());
            }
        } else {
            View decor = getWindow().getDecorView();
            int flags = decor.getSystemUiVisibility();
            if (showStatusBar) flags &= ~View.SYSTEM_UI_FLAG_FULLSCREEN;
            else flags |= View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE;
            decor.setSystemUiVisibility(flags);
        }
    }

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
        readerSystemBarsChannel = new MethodChannel(
            engine.getDartExecutor().getBinaryMessenger(), "openlib/reader_system_bars");
        readerSystemBarsChannel.setMethodCallHandler((call, result) -> {
            if ("setReaderActive".equals(call.method)) {
                cancelStatusBarAnimation();
                readerActive = Boolean.TRUE.equals(call.arguments);
                if (readerActive) readerControlsVisible = false;
                updateReaderStatusBar();
                result.success(null);
            } else if ("setControlsVisible".equals(call.method)) {
                readerControlsVisible = Boolean.TRUE.equals(call.arguments);
                if (readerActive) animateReaderStatusBar();
                result.success(null);
            } else {
                result.notImplemented();
            }
        });
    }
    @Override protected void onResume() {
        super.onResume();
        timer().setForeground(true);
        timer().setFocused(hasWindowFocus());
        if (readerActive) {
            cancelStatusBarAnimation();
            updateReaderStatusBar();
        }
    }
    @Override protected void onPause() {
        cancelStatusBarAnimation();
        timer().setForeground(false);
        super.onPause();
    }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        timer().setFocused(focused);
        if (focused && readerActive) {
            cancelStatusBarAnimation();
            updateReaderStatusBar();
        }
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
        cancelStatusBarAnimation();
        if (readerTimer != null) readerTimer.destroy();
        if (readerChannel != null) readerChannel.setMethodCallHandler(null);
        if (readerSystemBarsChannel != null) readerSystemBarsChannel.setMethodCallHandler(null);
        super.onDestroy();
    }
}
