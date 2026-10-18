package dev.wath.openlibextended;

/** Runs with an ordinary JDK; all times are virtual, no ten-minute sleeps. */
public final class ReaderInactivityTimerTest {
    static int checks;
    static void check(boolean ok, String message) {
        checks++;
        if (!ok) throw new AssertionError(message);
    }
    static final class Harness implements ReaderInactivityTimer.Clock,
            ReaderInactivityTimer.Scheduler, ReaderInactivityTimer.DisplayLock {
        long time, due, safetyDeadline;
        int acquisitions, releases, posts;
        boolean held;
        Runnable pending;
        final ReaderInactivityTimer timer = new ReaderInactivityTimer(this, this, this);
        public long now() { return time; }
        public void schedule(Runnable task, long delay) {
            check(pending == null, "only one pending deadline");
            pending = task; due = time + delay; posts++;
        }
        public void cancel(Runnable task) { if (task == pending) pending = null; }
        public void hold(long maximum) {
            held = true; acquisitions++; safetyDeadline = time + maximum;
        }
        public void release() { held = false; releases++; }
        void advance(long delta) {
            long target = time + delta;
            while (pending != null && due <= target) {
                time = due;
                Runnable task = pending; pending = null; task.run();
            }
            time = target;
        }
        void open() {
            timer.setForeground(true); timer.setFocused(true); timer.setReading(true);
        }
    }
    public static void main(String[] args) {
        final long minute = 60_000;
        Harness h = new Harness();
        h.timer.setForeground(true); h.timer.setFocused(true); h.timer.interact();
        check(!h.held && h.pending == null, "library uses system timeout");
        h.open(); check(h.held, "opening a book keeps screen on");
        h.advance(10 * minute - 1); check(h.held, "no early expiration");
        h.advance(1); check(!h.held && h.pending == null, "expires at exactly ten minutes");
        h.timer.interact(); check(h.held, "interaction after expiry starts a new period");
        h.advance(9 * minute); h.timer.interact();
        h.advance(minute); check(h.held, "old deadline cannot release renewed session");
        h.advance(9 * minute - 1); check(h.held, "renewal lasts until final millisecond");
        h.advance(1); check(!h.held, "ten minutes since final interaction");

        h = new Harness(); h.open();
        h.advance(minute); h.timer.setReading(false);
        check(!h.held && h.pending == null, "closing book releases immediately");
        h.timer.interact(); check(!h.held, "library interactions cannot acquire a lock");
        h.timer.setReading(true); check(h.held, "reopening works");
        h.timer.setForeground(false); check(!h.held && h.pending == null, "background releases");
        h.advance(20 * minute); h.timer.interact(); check(!h.held, "no background reactivation");
        h.timer.setForeground(true); check(h.held, "resume arms reader");
        h.timer.setFocused(false); check(!h.held && h.pending == null, "another window releases");
        h.timer.interact(); check(!h.held, "unfocused input ignored");
        h.timer.setFocused(true); check(h.held, "focus return arms reader");
        h.timer.destroy(); check(!h.held && h.pending == null, "destruction cancels everything");

        h = new Harness(); h.open();
        int posts = h.posts;
        for (int i = 0; i < 2000; i++) { h.advance(10); h.timer.interact(); }
        check(h.posts == posts, "pointer moves do not churn deadline callbacks");
        check(h.acquisitions == 21, "OS calls limited to one per second during gestures");
        check(h.safetyDeadline >= h.time + 10 * minute, "bounded OS lock covers final input");
        h.advance(10 * minute); check(!h.held, "long pinch or drag also resets full timeout");
        h = new Harness(); h.open(); h.advance(10 * minute);
        h.timer.setReading(false); h.timer.setForeground(false); h.timer.destroy();
        check(h.releases == 1, "cleanup after expiry is idempotent");
        System.out.println("Reader inactivity: " + checks + " checks passed");
    }
}
