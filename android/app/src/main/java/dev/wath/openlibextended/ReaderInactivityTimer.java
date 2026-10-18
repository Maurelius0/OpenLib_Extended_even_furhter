package dev.wath.openlibextended;

/** One deadline, no polling, animations, global settings or background service. */
final class ReaderInactivityTimer {
    static final long TIMEOUT_MS = 10 * 60 * 1000L;
    interface Clock { long now(); }
    interface Scheduler {
        void schedule(Runnable task, long delay);
        void cancel(Runnable task);
    }
    interface DisplayLock {
        void hold(long maximumDuration);
        void release();
    }
    private final Clock clock;
    private final Scheduler scheduler;
    private final DisplayLock display;
    private final Runnable expiry = this::checkDeadline;
    private boolean reading, foreground, focused, scheduled, holding;
    private long lastInteraction, lastRenewal;

    ReaderInactivityTimer(Clock clock, Scheduler scheduler, DisplayLock display) {
        this.clock = clock;
        this.scheduler = scheduler;
        this.display = display;
    }
    void setReading(boolean value) {
        if (reading == value) return;
        reading = value;
        updateEligibility();
    }
    void setForeground(boolean value) {
        if (foreground == value) return;
        foreground = value;
        updateEligibility();
    }
    void setFocused(boolean value) {
        if (focused == value) return;
        focused = value;
        updateEligibility();
    }
    private boolean eligible() { return reading && foreground && focused; }
    private void updateEligibility() {
        if (eligible()) interact();
        else stop();
    }
    void interact() {
        if (!eligible()) return;
        lastInteraction = clock.now();
        // Bound the OS lock too, so even a stalled UI cannot keep it indefinitely.
        // Coalesce high-rate pointer moves to at most one OS call per second.
        if (!holding || lastInteraction - lastRenewal >= 1000) {
            display.hold(TIMEOUT_MS + 1000);
            holding = true;
            lastRenewal = lastInteraction;
        }
        if (!scheduled) {
            scheduled = true;
            scheduler.schedule(expiry, TIMEOUT_MS);
        }
    }
    private void checkDeadline() {
        scheduled = false;
        if (!eligible()) { stop(); return; }
        long remaining = TIMEOUT_MS - (clock.now() - lastInteraction);
        if (remaining > 0) {
            scheduled = true;
            scheduler.schedule(expiry, remaining);
        } else stop();
    }
    private void stop() {
        scheduler.cancel(expiry);
        scheduled = false;
        if (holding) display.release();
        holding = false;
    }
    void destroy() {
        reading = foreground = focused = false;
        stop();
    }
}
