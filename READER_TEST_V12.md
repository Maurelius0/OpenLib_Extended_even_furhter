# Reader test v12

Adds a ten-minute inactivity period while an EPUB or PDF reader is open.
Native Android input tracking covers book pages (including WebViews), reader
controls, dialogs and the image viewer without sending pointer moves to Dart.
Each touch/key interaction restarts the period. The library, another app,
loss of window focus, screen-off and Activity destruction release the lock.
No system timeout value is read or changed, and no new permissions are added.

The implementation uses a bounded SCREEN_BRIGHT_WAKE_LOCK without
ON_AFTER_RELEASE or ACQUIRE_CAUSES_WAKEUP. The former would add the system's
normal inactivity timeout after the reader deadline; the latter could interfere
with manual screen-off. Although the screen-lock constant is deprecated, the
standard keep-screen-on window flag does not provide the required timed release
without restarting Android's normal timeout. The lock never raises the user's
chosen brightness. Its independent OS expiry is at most one second beyond the
reader deadline if the UI thread stalls. Device policies and Android's own
attention/accessibility features can still affect final screen-off behavior.

One delayed callback checks an absolute inactivity deadline; there is no polling
or background service. Native lock renewal is coalesced to once per second
during continuous gestures. Pausing the Activity cancels the callback and
releases the lock immediately. The existing reader shell owns the session, so
opening and closing its image viewer does not create competing sessions.

## Validation

The standalone Java test uses virtual time to verify the exact deadline,
renewal, gestures, background/focus changes, re-entry and cleanup. With a JDK:

```sh
mkdir -p /tmp/openlib-reader-timeout-tests
javac -d /tmp/openlib-reader-timeout-tests \
  android/app/src/main/java/dev/wath/openlibextended/ReaderInactivityTimer.java \
  android/reader-tests/dev/wath/openlibextended/ReaderInactivityTimerTest.java
java -cp /tmp/openlib-reader-timeout-tests \
  dev.wath.openlibextended.ReaderInactivityTimerTest
flutter test --no-pub test/reader_screen_timeout_test.dart
```

The widget test checks reader entry, an overlaid route and return to the library.
EPUB/PDF reader, image viewer, fonts, pagination, library and styling regressions
are also checked. A physical Pixel timeout measurement remains a device check.
Install the APK over the existing Reader Test app to keep the library/settings.
