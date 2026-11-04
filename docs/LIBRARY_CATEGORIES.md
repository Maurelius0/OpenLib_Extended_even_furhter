# Library category consistency

## Reproduced faults

The library status provider initially contained null, which means no filter.
The first library view therefore included unread, in-progress and completed
books. Selecting In Progress and then Unread finally applied the unread filter.
The status chips could also return to the unfiltered state by deselecting the
active chip. This did not represent a database status migration.

Separately, successful downloads inserted their database row without notifying
the cached library providers. The categorized provider also fetched its own
book list rather than depending on the main library list, so existing refreshes
for imports and restores did not propagate to it.

## Fix

- Start with Library selected, showing every downloaded book regardless of status.
- Keep one category selected; tapping the current category is idempotent.
- Library replaces the former Unread chip. In Progress and Completed retain their
  status filters. Internal unread metadata is preserved.
- Default to newest added first, with the existing saved sort order, search and
  tag filters applying across categories.
- Notify the main library only after a downloaded book is saved successfully.
- Derive the categorized book list from the main library provider, so downloads,
  imports and restores use the same source.
- Preserve the current category during refresh, and retain saved positions,
  completion flags, tags, sorting and search behavior.

The download notification uses one broadcast event per successfully saved book;
progress events do not trigger database reloads. The provider owns and disposes
its subscription. No dependencies, database migrations or native changes were
introduced. The controls retain their existing layout and styling.

## Verification

Before the later Library-category adjustment, regression checks were run against
the original source: all three
startup/category tests failed because the initial category was null, and the
local-download test timed out waiting for the cached book list to refresh.
Restoring that fix made all 24 library tests pass. After the approved Library
adjustment, all 24 updated library checks and seven localization checks pass.

The download regression uses the real DownloadManager, a local HTTP server and
SQLite. It starts with unread, in-progress and completed books, downloads a
checksum-valid file while In Progress is selected, waits for automatic refresh,
and verifies Library shows the new book first, followed by the existing finished,
in-progress and unread books. The existing in-progress and completed books
retain their categories.
It also verifies the main library cache updates from three to four books.

Additional download-manager, image-viewer, EPUB-resource and reader-shell checks
passed. All four PDF checks passed after setting the existing PDFIUM_PATH test
option to the downloaded native test library. Targeted Dart analysis reports no
issues, and git diff --check passes.

Commands for an installed Flutter toolchain:

```bash
flutter test test/library_status_tabs_test.dart \
  test/library_download_status_test.dart test/library_organization_test.dart
flutter test test/download_manager_test.dart test/reader_image_viewer_test.dart \
  test/epub_resources_test.dart test/book_reader_shell_test.dart
PDFIUM_PATH=/absolute/path/to/libpdfium.so flutter test test/pdf_viewer_test.dart
dart analyze lib/state/state.dart lib/services/download_manager.dart \
  lib/ui/mylibrary_page.dart test/library_status_tabs_test.dart \
  test/library_organization_test.dart test/library_download_status_test.dart
```

No new APK was built, and this change has not been tested on a physical Pixel.
The published v13 APK is unchanged. The source preserves the saved v15 reader
improvements; the development signing key remains excluded from GitHub.
