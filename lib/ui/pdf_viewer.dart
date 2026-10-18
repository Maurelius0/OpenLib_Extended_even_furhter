// Built-in PDF reader for every platform, powered by pdfrx (PDFium).
// Replaces the old split of mobile-only flutter_pdfview plus a desktop
// shell-out to the system viewer - one interactive viewer everywhere,
// with text selection built in.

// Flutter imports:
import 'package:openlib/ui/components/book_reader_shell.dart';
import 'package:openlib/services/database.dart';

import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfrx/pdfrx.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/ui/components/snack_bar_widget.dart';

import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        openPdfWithExternalAppProvider,
        getBookPosition,
        savePdfPosition,
        libraryBooksProvider;

Future<void> launchPdfViewer({
  required String fileName,
  required BuildContext context,
  required WidgetRef ref,
}) async {
  bool openWithExternalApp = ref.watch(openPdfWithExternalAppProvider);

  // The user can always prefer the external app; pdfrx covers every
  // platform in-app otherwise.
  if (openWithExternalApp) {
    try {
      String path = await getFilePath(fileName);
      await OpenFile.open(path, linuxByProcess: true, type: "application/pdf");
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
          context: context,
          message: "File not found. The download may have failed.",
        );
      }
    }
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) {
          return PdfViewPage(fileName: fileName);
        },
      ),
    );
  }
}

class PdfViewPage extends ConsumerStatefulWidget {
  const PdfViewPage({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PdfViewPageState();
}

/// Saved positions are stored as decimal strings; anything unparsable
/// or out of range means "start from the top".
@visibleForTesting
int initialPageFor(String? saved) {
  final page = int.tryParse(saved ?? '');
  if (page == null || page < 1) return 1;
  return page;
}

class _PdfViewPageState extends ConsumerState<PdfViewPage>
    with WidgetsBindingObserver {
  int _page = 1, _pageCount = 0;
  bool _restored = false;
  PdfDocumentRef? _documentRef;
  String? _documentPath;

  PdfDocumentRef _documentFor(String path) {
    if (_documentPath != path) {
      _documentPath = path;
      _documentRef = PdfDocumentRefFile(path, useProgressiveLoading: false);
    }
    return _documentRef!;
  }

  VoidCallback? _toggleControls;
  Future<void> _writes = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _save() {
    if (!_restored || _pageCount < 1) return;
    final page = _page;
    _writes = _writes
        .then((_) => savePdfPosition(widget.fileName, page))
        .catchError((Object error) {
      debugPrint('Could not save PDF position: $error');
    });
  }

  void _turn(int delta) {
    final next = (_page + delta).clamp(1, _pageCount).toInt();
    if (next == _page) return;
    setState(() => _page = next);
    _save();
    final activityPage = _page;
    _writes = _writes.then((_) async {
      final changed = await MyLibraryDb.instance.recordReaderPage(
          widget.fileName, activityPage > 1 ? 'pdf:$activityPage' : null);
      if (changed && mounted) ref.invalidate(libraryBooksProvider);
    }).catchError((Object e) {
      debugPrint('Could not save reading activity: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void dispose() {
    _save();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BookReaderShell(
      title: widget.fileName,
      progress: _pageCount == 0 ? 'Loading…' : '$_page / $_pageCount',
      previous: _page > 1 ? () => _turn(-1) : null,
      next: _page < _pageCount ? () => _turn(1) : null,
      onToggleReady: (toggle) => _toggleControls = toggle,
      child: ref.watch(filePathProvider(widget.fileName)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Unable to open PDF: $e')),
            data: (path) => ref.watch(getBookPosition(widget.fileName)).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('Unable to load position: $e')),
                  data: (saved) => PdfDocumentViewBuilder(
                    documentRef: _documentFor(path),
                    errorBuilder: (context, error, stackTrace) =>
                        Center(child: Text('Unable to render PDF: $error')),
                    builder: (context, document) {
                      if (document == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final count = document.pages.length;
                      if (count == 0) {
                        return const Center(
                          child: Text('This PDF has no pages.'),
                        );
                      }
                      if (!_restored) {
                        _restored = true;
                        _writes = _writes.then((_) async {
                          await MyLibraryDb.instance
                              .recordReaderPage(widget.fileName, null);
                          if (mounted) ref.invalidate(libraryBooksProvider);
                        });
                        _pageCount = count;
                        _page = initialPageFor(saved).clamp(1, count).toInt();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() {});
                        });
                      }
                      return LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final fraction =
                                details.localPosition.dx / constraints.maxWidth;
                            if (fraction < .3) {
                              if (_page > 1) _turn(-1);
                            } else if (fraction > .7) {
                              if (_page < _pageCount) _turn(1);
                            } else {
                              _toggleControls?.call();
                            }
                          },
                          onHorizontalDragEnd: (details) {
                            final speed = details.primaryVelocity ?? 0;
                            if (speed < -100 && _page < _pageCount) _turn(1);
                            if (speed > 100 && _page > 1) _turn(-1);
                          },
                          child: PdfPageView(
                            document: document,
                            pageNumber: _page,
                            key: ValueKey(_page),
                            maximumDpi: 200,
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
    );
  }
}
