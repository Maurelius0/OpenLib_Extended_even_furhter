# Reader system status bar and high-refresh-rate verification

## Implementation
The EPUB and PDF reading pages both use `BookReaderShell`. Its overlay controls
now toggle the **real Android status bar**, leaving Android's bottom navigation
bar visible and functional. When leaving the reader, normal status bar
visibility returns. The reader reserves its original safe-area height while
the status bar is hidden so opening the menu does not repaginate the book.

On Android 11+, the native activity uses `WindowInsetsController` to hide/show
`WindowInsets.Type.statusBars()` rather than Flutter's deprecated fullscreen
mode, which is ignored with modern enforced edge-to-edge. Android 10 and
earlier use legacy window flags. Other platforms are unaffected.

The custom book loading animation already uses `AnimationController` with
`vsync`, a wall-clock duration of 3 seconds, and a
`CustomPainter(repaint: animation)`; it is not locked to 60 FPS. Other
visible Flutter animations also use duration-based framework primitives.
The OS may still choose a lower refresh rate because of power or thermal
settings. Do not force 120 Hz globally.

## Checks before publishing an APK
- `flutter test test/book_reader_shell_test.dart`.
- Open an EPUB and a PDF on Android 16/17: the system status icons disappear
  when controls are closed; appear when the center menu opens; disappear
  again when it closes; and return normally after leaving the reader.
- Check that the bottom navigation gesture/area still works.
- Check text/page positions before and after opening the menu, including
  rotation and changing the light/dark reading theme.
- Check EPUB footnote/image viewer and PDF navigation for regressions.
- In the device's 120 Hz display mode, observe the book loading animation
  using Flutter DevTools frame timings (8.33 ms display interval) and ensure
  there is no 60 FPS lock or excessive frame work; repeat at 60 Hz and with
  battery saver enabled.
- Test notifications/quick settings pulled down via Android's usual gesture.

No APK or device performance validation is implied by this source change.

## Reader controls fade (v19)

- EPUB and PDF overlays fade in and out in 150 milliseconds (both the top
  controls and bottom navigation). The underlying page has unchanged bounds.
- Flutter uses vsync-timed `AnimatedSwitcher` crossfades; invisible outgoing
  overlays cannot accept taps or appear in accessibility semantics.
- Android 11+ requests a 150 ms alpha transition of the actual system status
  bar using `WindowInsetsController.controlWindowInsetsAnimation`. If the
  system refuses to grant animation control, the original show/hide commands
  remain the fallback; exact cross-process synchronization is not guaranteed.
- Android system "Remove animations" disables the custom status-bar fade;
  Flutter reduced-animation mode skips the menu fade.
- Test both EPUB and PDF on the Pixel 8: normal show/hide, repeated rapid
  center taps, page bounds unchanged, focus loss/resume, device rotation,
  light/dark appearance, and native status/navigation gestures.
