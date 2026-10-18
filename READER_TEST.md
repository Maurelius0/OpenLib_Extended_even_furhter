# Openlib Reader Test

Private Android test fork of warreth/OpenlibExtended, based on commit
3359940a443c0226d6cae63c661481db4ce572f5. Original AGPL-3.0 license applies.

Reader changes:
- EPUB pages use a local Android WebView with serif typography, warm light/dark colors,
  a font-size slider, section contents, left/right tap zones, and horizontal swipes.
- EPUB position stores the section and visible text offset, rather than a page number,
  so resizing text can retain the reading location.
- PDF displays one fitted page, with tap zones and horizontal swipes. Zoom is omitted.
- Both readers save on page changes and when backgrounded or closed.
- Centre taps hide controls without changing the available page dimensions.
- Test application ID: dev.wath.openlibextended.readertest.
- Test application label: Openlib Reader Test.
- Upstream automatic update prompts are disabled for this application ID.

Build with Flutter 3.47.7, JDK 17 and Android SDK 36:

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64
```

If no release keystore is configured, this private test build uses Android's debug
signing key. Preserve that key if making installable updates to the same test app.

Validation:
- Relevant Dart files pass static analysis.
- Ten selected Flutter tests pass, including real EPUB parsing, PDF rendering,
  PDF page buttons and tap zones, saved PDF position, and stable reader layout.
- Browser tests exercise EPUB pagination across every generated page, taps,
  text-position restoration, text-size reflow, section boundaries and centre controls.

Limitations of this initial implementation:
- Android phone testing is still needed. No on-device validation has been performed.
- EPUB uses section-relative page counts; it does not compute a whole-book page total.
- Reader typography replaces publisher styles. Fixed-layout EPUBs, complex tables,
  unusual SVG features and fixed-layout styling need further phone testing.
- The previous EPUB text-to-speech controls are not included in this reader.
- PDFs keep their printed page colors; dark app chrome does not recolor PDF pages.
- Existing EPUB scroll/CFI positions are not migrated into the new reader.
- The separately installed test app begins with its own local library and preferences.

## Reader test update 2

Fixes the first-open error `Preference pagedEpub:<filename> not found`.
Saved position, text size and theme preferences are optional and use defaults
when absent. Other database errors still propagate. Five new tests cover fresh
databases, existing reading settings, saved positions, malformed preferences
and the original required-preference contract. The latest targeted run passed
11 tests; static analysis of the changed files passed.

The ARM64 Dart application was rebuilt with the same Flutter 3.47.7 engine and
repackaged into the verified original Android shell. The package manifest,
plugins, assets and other native libraries are unchanged. The updated APK was
aligned for 16 KiB pages and signed with the original test key, so it can be
installed over the first test app. Android version code remains 14.

## Reader test update 3

- Local links in the EPUB contents page and chapter menu now navigate to the
  target section and fragment page. EPUB 3 navigation documents and nested NCX
  chapter entries retain their destinations.
- Inline SVG covers embed their local images and fit within the reading page.
- Long-press an EPUB illustration or cover to open an image viewer with pinch
  zoom (up to 8x), panning, reset zoom and Back. Returning preserves the page.
- Books move to In Progress after two different pages beyond the initial cover
  page are visited. Activity is persisted independently from resume position;
  simply opening, restoring or changing text size does not count. This applies
  to EPUB and PDF. Completed books retain their completed status.
- The font-size slider is retained.

Install over v2 without uninstalling, to keep the local library and settings.
The update uses the original Android shell and signing certificate, with rebuilt
ARM64 Dart code and the updated pagination JavaScript asset.

Validation for update 3: 21 selected Flutter tests passed (EPUB parsing/resources,
preferences/activity, image viewer, reader shell, EPUB errors and PDF page controls).
Changed production files passed static analysis. Browser checks passed SVG cover
layout, local link dispatch, fragment pagination, image opening, touch long-press
and suppression of accidental page turns. Phone testing of this update remains
necessary, especially with the specific EPUB that showed a blank cover.

## Reader test update 4

- EPUB navigation slider spans every page in the spine, including chapters and
  the cover. Drag to preview a destination page number, then release to jump.
  Existing edge taps, swipes, contents links and font-size controls remain.
- All reader app controls, including progress labels and the slider, start
  hidden. A centre tap shows them; a second centre tap hides them. Controls
  overlay the content, so toggling them never resizes or repaginates it.
- Whole-book counts are measured offscreen using the same layout as the live
  page. They are recomputed when text size or viewport dimensions change.
  The menu displays “Preparing book pages…” until counting is complete; normal
  page turns remain available during preparation. Large illustrated books may
  take longer to count. Counts are specific to the current text size/layout.
- Library entries pointing to the exact same file are consolidated, keeping
  the fullest metadata and combining tags. Reading position is unchanged and
  book files are not deleted. Late folder scans no longer add coverless entries
  for files already represented by a richer download entry. Different files
  with identical titles remain separate.

Validation: 23 selected Flutter tests passed and changed files passed static
analysis. Browser tests verified measured and live page counts at two font
sizes, rotation, direct page seeking, side taps and centre control taps.
Phone testing of this version remains necessary.

## Reader test update 5

- Reader WebView widget and prepared chapter bodies are retained across UI
  updates. Parsing/preparing EPUB HTML and embedded images runs once in a worker
  isolate instead of repeating in Flutter's UI thread during slider movement.
- The whole-book slider owns its drag-preview state and commits one navigation
  request on release. Slider changes do not rebuild the reader or its parent.
  Whole-book page navigation, middle-tap menus and tap/swipe turns are retained.
- Previous/next corner buttons are removed from the reader overlay.
- Byte-identical book files under different filenames are displayed once, using
  the richest metadata. Fingerprints are streamed and cached by file size/mtime;
  only possible same-size duplicates are hashed. Tags and missing reading state
  are copied to the displayed entry. All original files and distinct-content
  editions are retained. Copies with different byte contents remain separate.

Validation: 25 selected Flutter tests passed, including isolate preparation,
local slider drag state, release-only seeking, removal of arrows, duplicate
content across filenames, preservation of files and distinction of different
contents. Static analysis is clean. Browser pagination/navigation checks pass.
Performance improvements are not yet timed or verified on the user's Pixel.

## Reader test update 6

- Retains supported publisher typography from local linked stylesheets, local
  CSS imports, style blocks and inline declarations. Rules are scoped per section.
  Headings, bold/italic text, alignment, spacing, lists and font shorthand are
  preserved. Fixed font sizes become relative sizes so the text slider works.
  The reader retains theme colours and page geometry; scripts, remote resources,
  font-face downloads and layout/animation CSS remain excluded. This is a
  reflowable reader, not a full publisher fixed-layout renderer.
- Confirmed against the supplied EPUB: both reported headings use a styled
  paragraph class with 1.41667em text and bold weight. Their CSS is now retained
  without special-casing the strings. Browser checks verified them at two text
  sizes, exact page counts and contents anchors with publisher formatting.
- Slider dragging shows actual page previews, limited to about seven requests
  per second. Only one preview navigation can be in flight. Fast motion replaces
  queued requests; release waits for any in-flight request and commits the exact
  selected page. Cached prepared chapters and current column layout are reused;
  no second WebView or image-thumbnail cache is allocated. Temporary previews do
  not mark pages as read or overwrite saved position while dragging.
- Replaced the image viewer refresh icon with a labelled Reset zoom button. It
  restores the fitted image size and centres the image; no file/network reload.
- Duplicate/library handling remains unchanged from v5.

Validation: 30 selected Flutter tests passed, including the supplied EPUB smoke
check, stylesheet filtering and heading styles, preview coalescing/serialization,
exact final selection, image zoom reset, and existing reader/library behaviour.
Changed files pass static analysis. Browser checks used the real prepared EPUB
chapter and verified heading sizes/weights, font scaling, live versus measured
pagination, temporary previews, exact commits and contents links. On-device
preview performance still requires testing on the Pixel. The supplied book is
not included in the source archive; optional smoke tests use environment paths.

## v7: Library status tabs and image viewer controls

- Keep Unread, In Progress and Completed visible with any library size, including
  zero or one book. Previously the row required multiple books or an active
  filter, so consolidating duplicate entries could hide all three controls.
- Keep status controls available when a filter has no matching books, so readers
  can change or clear it immediately.
- Remove the image viewer heading and Reset zoom action. Pinch zoom, panning and
  back navigation remain available.
- Widget regression coverage exercises all three statuses with zero, one and
  multiple books, empty filter results, clearing filters, and image viewer zoom
  and back navigation without the removed controls.

Validation: 52 Flutter tests passed. One optional supplied-EPUB smoke test was
skipped because the original attachment was unavailable. Static analysis passed
for changed Dart files. Device verification remains to be done on the Pixel.

## v8: Swipe down to close images

- A deliberate one-finger downward swipe closes the image viewer and returns to
  the same book page when the image is fitted at normal size.
- Zoomed images retain panning in every direction; pinch gestures and two-finger
  movement never dismiss the viewer. Short, upward and mostly sideways drags do
  not close it. Back navigation remains available at any zoom level.
- Observes pointer events alongside InteractiveViewer without another gesture
  recognizer, dependency, image copy or per-frame widget rebuild.

Validation: 59 Flutter tests passed, covering downward dismissal, small and
sideways drags, zoomed panning, actual pinch gestures, changing finger counts,
cancelled touches, Back navigation, library status tabs and existing EPUB/PDF
reader behavior. The optional supplied-EPUB smoke test was skipped because its
attachment was unavailable. Changed Dart files pass static analysis. Device
verification remains to be done on the Pixel.

## v9: Offline font choices and image captions

- Adds a font-family picker immediately beside Reading settings (the text-size
  control). Both remain part of the centre-tap overlay and start hidden.
- Ten standard choices: Literata, Lora, Libre Baskerville, Source Serif 4,
  EB Garamond, Noto Serif, Source Sans 3, Nunito, Atkinson Hyperlegible and Lexend.
  OpenDyslexic is the additional dyslexia-oriented choice. Book default restores
  the original typography; the choice persists across books and restarts.
- Fonts and their OFL licenses are bundled for offline use (about 5.2 MiB). Only
  the selected family is embedded in the reading document. There are no new app
  dependencies or font-service requests. WOFF2 files retain upstream glyph sets;
  pinned source URLs and hashes are recorded in the bundled manifest.
- Font selection preserves bold, italic, heading sizes and the current reading
  passage. The pagination layout key includes font choice. Live navigation and
  offscreen page counting wait for font loading. Font overrides skip code,
  mathematics and SVG elements.
- Images display meaningful title attributes, SVG titles, figure captions,
  linked accessibility labels or descriptive alt text when provided. Generic
  labels such as Image and file-name placeholders do not become headings.
- Removes the image viewer back arrow. Swipe down at fitted size and Android
  system Back still close it; zoomed dragging remains panning. Untitled images
  have no toolbar. No OCR or inferred titles are added.
- The supplied EPUB contains 103 image elements with alt="Image" and no image
  title attributes or figure captions, so those have no separate viewer header.

Validation: 65 Flutter tests passed, with none skipped. Static analysis is clean.
Browser tests used the supplied EPUB and verified every bundled font loads under
an offline-only content policy, including matching live/offscreen page counts,
preserved reading passages, bold/italic/headings, publisher font reset and font
size changes. Navigation, slider previews, contents links and image metadata
extraction also passed browser checks. Pixel device verification remains to be
done. The supplied EPUB is not included in the source archive.

## v10: Centred book title and separate reader toolbar

- The reader overlay gives the complete book title a centred, full-width area.
  It wraps naturally instead of truncating to one line.
- Library, contents, font family and text-size/settings controls sit in a compact
  centred toolbar below the title, separated by a subtle rule. The font and size
  buttons stay grouped together. The warm panel has rounded lower corners.
- Extremely long titles and large accessibility text can scroll within the title
  area while the toolbar stays available. The header stays above the middle tap
  region, so the centre still toggles the overlay.
- Both rows remain hidden during reading and overlay the same page viewport.
  EPUB and PDF pagination, saved positions and image-viewer controls are unchanged.

Validation: 68 Flutter tests passed with none skipped. New checks cover complete
multiline titles on portrait and landscape phone viewports, centring, toolbar
placement and callbacks, large text, very long titles and unchanged page bounds.
Static analysis is clean. The header was rendered with bundled UI fonts and
visually reviewed. Pixel device verification remains to be done.

## v11: Leading library arrow and current reading part

- Moves the library/back arrow to the far left of the toolbar. The remaining
  controls stay centred, with the font and text-size controls grouped together.
- Adds the current EPUB chapter or subsection below the book title, in smaller,
  softer text. Both titles remain centred, wrap naturally and hide with the menu.
- Uses the book's actual contents labels and anchors, including multiple chapters
  inside one spine file. A body heading can supply a fallback section name.
- Prepares labels once with the book in the existing worker isolate. Anchor page
  positions are cached per layout and refreshed after font, text-size or viewport
  changes. Page turns and slider previews report the current part through the
  existing reader message, without reparsing the book or resizing the page.

Validation: 72 Flutter tests passed with none skipped. Browser checks verified
section changes on seeking and previews, cached marker positions between page
turns, font size/family changes, rotation and existing page navigation. The
supplied book correctly reports Chapter 1, Chapter 2, What is money? and The
Fundamentals. The revised header was rendered and visually reviewed. Static
analysis is clean. Pixel device verification remains to be done.
