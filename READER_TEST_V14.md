# Reader test v14

EPUB illustrations now open with a single tap. Raster images and inline SVG
figures retain captions, pinch zoom and short-swipe slide/fade dismissal.
Swipes starting over an image still turn pages, and multi-finger gestures do
not activate images or links. A picture wrapped in a link opens the picture;
an explicit hyperlink inside an SVG diagram retains its link behavior.

Website links were previously discarded during EPUB sanitization. HTTP/HTTPS
links are now retained as app-dispatched targets and open in the external
browser only after a user action. Executable/local-file schemes, remote image
loads and publisher scripts remain blocked. The existing url_launcher plugin
is reused; no runtime dependencies or permissions are added.

Internal links retain safe native link hit testing and are dispatched directly
on a short touch release rather than relying on synthesized WebView clicks.
The handler suppresses duplicate clicks, preserves keyboard activation, and
resolves normalized/decoded reading-spine file paths plus id/name fragments.
Named anchors without href are no longer turned into spurious self-links.
Unavailable reading sections or failed browser launches show an error message.
The approved controls, publisher typography, progress and inactivity policy
are unchanged.

## Validation

- 80 Flutter tests passed, including the supplied EPUB, with no optional fixture
  skips in this run. The real-book test checks over 100 local and 300 website
  links after sanitization and validates all local destinations and anchors.
- Chromium tests exercise trusted touch, mouse/keyboard navigation, one-shot
  internal/external link routing, raster/SVG image taps and captions, explicit
  SVG hyperlinks, swipes over images, multi-touch rejection and fragment jumps.
- Six real-book links were tapped in Chromium and their destination pages and
  anchor visibility verified. These checks use the exact prepared book HTML and
  pagination script; they do not contact the external websites.
- Targeted Dart analysis is clean. The release APK is signed with the existing
  Reader Test key and checked for 16KB alignment. Its changed payloads are the
  Dart AOT library and pagination script; existing native code/assets remain.

External browser handoff and touch timing on the physical Pixel remain device
checks. This release changes the EPUB reader; PDF link annotations are not
handled by this patch. Broken book destinations cannot be reconstructed.

`tool/test_epub_pagination.cjs` runs the browser regressions. To validate a real
book, set READER_TEST_EPUB and READER_LINK_FIXTURE when running
`test/epub_links_real_book_test.dart`, then pass the exported JSON through
READER_LINK_FIXTURE to `tool/test_epub_book_links.cjs`. Browser scripts use
Playwright and READER_CHROMIUM_PATH. Fixtures are not included in the source ZIP.
