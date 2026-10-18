# Reader test v13 — approved design

The reader design was approved on 17 October 2026. This version packages the
approved controls and image dismissal in the Reader Test app update.

- Inline minus / A / plus controls replace the font-size bottom sheet.
  The existing 12–32 size range and saved preference are retained.
- Full centered book title uses 15px instead of 18px, with less top padding.
  Current reading part remains below it at 12px.
- Light/dark toggle appears at the right of the toolbar and persists its setting.
- Whole-book slider sits low, has a 2px track and a 24×8 rounded rectangular
  handle, retaining a 48px touch area and accessible page announcements.
  A centered current/total whole-book page count sits above it and updates during
  preview dragging. The handle has a 0.75px background-colored outline inset
  1.5px from its edge (dark in dark mode, light in light mode).
- The old Section x/x footer is removed; only the new whole-book count remains. Tapping the center still
  toggles all controls without resizing the book or repaginating it.
- EPUB platform WebView has a transparent initial background, and the file-path
  loading screen uses warm reader paper rather than the app's default white.
  Startup flash removal still requires confirmation on a physical Pixel.
- A short downward image drag (48 logical pixels) initiates dismissal. The image
  and title follow the finger and fade; release finishes the downward exit in
  220ms. Short/cancelled drags spring back. Zoomed or multi-finger gestures do
  not dismiss. A transparent route reveals the book underneath. System Back
  remains supported, including during the exit animation.

The existing ten-minute inactivity behavior is unchanged. No runtime
packages, polling or network calls were added.

## Preview and validation

`tool/reader_preview_test.dart` renders the actual shared controls using
representative sample book text (the text is not extracted from the user's
EPUB). It exports light/dark screenshots and frames of a 55px downward swipe.
The render uses Nunito and Noto Serif converted from the bundled WOFF2 fonts to
TTF with fontTools/Brotli, placed in `toolchain/preview-fonts/` next to the output
folder. No preview font conversion or tooling runs in the app.

The selected EPUB, PDF, image, pagination, font, library, preference and timeout
regressions pass. New tests cover inline controls and both font-size limits,
theme visibility, short-swipe movement/fading, automatic dismissal and Back
while animating. The two optional tests requiring the real EPUB fixture are
skipped when that fixture is unavailable. Dart analysis of changed UI files and
the preview renderer is clean.
