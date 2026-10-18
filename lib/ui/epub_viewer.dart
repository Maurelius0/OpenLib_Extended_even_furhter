import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:openlib/ui/components/book_seek_slider.dart';
import 'package:flutter/services.dart';
import 'package:openlib/ui/components/reader_image_viewer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:epubx/epubx.dart';
import 'package:open_file/open_file.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/epub_pages.dart';
import 'package:openlib/services/epub_preferences.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/ui/components/reader_font_picker.dart';
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/ui/components/book_reader_shell.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        openEpubWithExternalAppProvider,
        libraryBooksProvider;

Future<void> launchEpubViewer({
  required String fileName,
  required BuildContext context,
  required WidgetRef ref,
}) async {
  try {
    String path = await getFilePath(fileName);
    bool openWithExternalApp = ref.watch(openEpubWithExternalAppProvider);

    // Check if user wants external app
    if (openWithExternalApp) {
      await OpenFile.open(
        path,
        linuxByProcess: true,
        type: "application/epub+zip",
      );
    } else {
      try {
        // Use internal Epub Viewer for all platforms (epub_view supports desktop)
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (BuildContext context) {
                return EpubViewerWidget(fileName: fileName);
              },
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          showSnackBar(context: context, message: "Unable to open epub!");
        }
      }
    }
  } catch (e) {
    // File doesn't exist or can't be accessed
    if (context.mounted) {
      showSnackBar(
        context: context,
        message: "File not found. The download may have failed.",
      );
    }
  }
}

class EpubViewerWidget extends ConsumerStatefulWidget {
  const EpubViewerWidget({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EpubViewState();
}

class _EpubViewState extends ConsumerState<EpubViewerWidget> {
  @override
  Widget build(BuildContext context) {
    final filePath = ref.watch(filePathProvider(widget.fileName));
    return filePath.when(
      data: (data) {
        return EpubViewer(filePath: data, fileName: widget.fileName);
      },
      error: (error, stack) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: Text(AppLocalizations.of(context).appTitle),
            titleTextStyle: Theme.of(context).textTheme.displayLarge,
          ),
          body: Center(child: Text(error.toString())),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xff211e1a),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xffe7dcc7))),
      ),
    );
  }
}

class EpubViewer extends ConsumerStatefulWidget {
  const EpubViewer({super.key, required this.filePath, required this.fileName});
  final String filePath, fileName;
  @override
  ConsumerState<EpubViewer> createState() => _EpubViewerState();
}

class _EpubViewerState extends ConsumerState<EpubViewer>
    with WidgetsBindingObserver {
  EpubBook? _book;
  List<String> _bodies = [];
  List<List<EpubReadingLabel>> _readingLabels = [];
  String _currentPart = '';
  Widget? _readerView;
  bool _previewing = false;
  Completer<void>? _chapterLoaded;
  final List<String> _spine = [];
  InAppWebViewController? _web;
  VoidCallback? _toggleControls;
  String? _error;
  String _script = '';
  String? _pendingAnchor;
  int? _pendingPage;
  List<int?> _sectionPages = [];
  String? _pageLayout;
  int _paginationJob = 0;
  bool _measuring = false;
  Timer? _paginationTimer;
  int? get _totalPages => _sectionPages.isEmpty || _sectionPages.contains(null)
      ? null
      : _sectionPages.cast<int>().fold<int>(0, (a, b) => a + b);
  int get _bookPage =>
      _sectionPages.take(_chapter).fold<int>(0, (a, b) => a + (b ?? 1)) + _page;

  bool _chapterNavigation = false;
  int _chapter = 0, _offset = 0, _page = 0, _count = 1;
  double _fontSize = 20;
  ReaderFont _font = ReaderFonts.bookDefault;
  String _fontCss = '';
  bool _dark = true, _ready = false, _loading = true, _lastPage = false;
  Future<void> _writes = Future.value();
  String get _positionKey => 'pagedEpub:${widget.fileName}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final prepared =
          await compute(prepareEpub, await File(widget.filePath).readAsBytes());
      final book = prepared.$1;
      _spine.addAll(prepared.$2);
      _bodies = prepared.$3;
      _readingLabels = prepared.$4;
      _sectionPages = List<int?>.filled(_spine.length, null);
      if (_spine.isEmpty) {
        throw const FormatException('No readable EPUB spine found');
      }
      final preferences = await EpubReaderPreferences.load(
          MyLibraryDb.instance, widget.fileName, _spine.length);
      _chapter = preferences.chapter;
      _currentPart = _readingLabels[_chapter].firstOrNull?.title ?? '';
      _offset = preferences.offset;
      _fontSize = preferences.fontSize;
      _dark = preferences.dark;
      _font = preferences.font;
      _fontCss = await ReaderFonts.loadCss(_font);
      _script = await rootBundle.loadString(
        'lib/ui/components/epub_pagination.js',
      );
      if (mounted) {
        setState(() {
          _book = book;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _save() {
    if (!_ready || _previewing) return;
    final position = jsonEncode({'chapter': _chapter, 'offset': _offset});
    _writes = _writes
        .then(
      (_) => MyLibraryDb.instance.savePreference(_positionKey, position),
    )
        .catchError((Object e) {
      debugPrint('Could not save EPUB position: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  @override
  void dispose() {
    _save();
    if (_chapterLoaded?.isCompleted == false) _chapterLoaded!.complete();
    _paginationTimer?.cancel();
    _paginationJob++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _document() {
    final body = _bodies[_chapter];
    final labels = jsonEncode(_readingLabels[_chapter]
            .map((label) => {'title': label.title, 'anchor': label.anchor})
            .toList())
        .replaceAll('<', r'\u003c');
    return """<!doctype html><html data-reader-font="${_font.id}" class="${_dark ? 'dark' : ''}"><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<style id="reader-font-face">$_fontCss</style>
<style>
:root{--size:${_fontSize}px;--paper:#f6efdf;--ink:#30291f}
:root.dark{--paper:#211e1a;--ink:#e7dcc7}
*{box-sizing:border-box}html,body{margin:0;height:100%;overflow:hidden;background:var(--paper);color:var(--ink)}
#viewport{position:absolute;inset:12px 24px;overflow:hidden}
.reader-section{height:100%;width:100%;column-width:calc(100vw - 48px);column-gap:48px;column-fill:auto;
font-family:Georgia,serif;font-size:var(--size);line-height:1.55;overflow-wrap:anywhere}
p{margin:0 0 .8em}h1,h2,h3{line-height:1.2;break-after:avoid}img,svg{max-width:100%;max-height:70vh;object-fit:contain;break-inside:avoid}svg{width:100%;height:70vh}a[data-reader-target]{color:inherit;text-decoration:underline;cursor:pointer}
table{max-width:100%;font-size:.8em}pre{white-space:pre-wrap}body{touch-action:pan-y}
</style></head><body><div id="viewport"><main id="book" class="reader-section">$body</main></div>
<script>window.readerSections=$labels;window.readerFontFamily=${jsonEncode(_font.family)};window.readerChapter=$_chapter;$_script</script></body></html>""";
  }

  Future<void> _openChapter(int chapter,
      {bool last = false, String? anchor, int? page}) async {
    if (chapter < 0 || chapter >= _spine.length || !_ready) return;
    _save();
    _paginationJob++;
    _measuring = false;
    setState(() {
      _ready = false;
      _chapter = chapter;
      _currentPart = _readingLabels[chapter].firstOrNull?.title ?? '';
      _offset = 0;
      _lastPage = last;
      _pendingAnchor = anchor;
      _pendingPage = page;
      _chapterNavigation = !_previewing;
    });
    _chapterLoaded = Completer<void>();
    await _web?.loadData(data: _document());
    await _chapterLoaded!.future
        .timeout(const Duration(seconds: 12), onTimeout: () {});
  }

  Future<void> _followLink(String target) async {
    final split = target.indexOf('#');
    final file = split < 0 ? target : target.substring(0, split);
    final anchor = split < 0 ? null : target.substring(split + 1);
    final chapter = _spine.indexWhere((name) => Uri.decodeFull(name) == file);
    if (chapter < 0) return;
    if (chapter == _chapter && anchor != null) {
      await _web?.evaluateJavascript(
          source: 'window.readerAnchor(${jsonEncode(anchor)})');
    } else {
      await _openChapter(chapter, anchor: anchor);
    }
  }

  Future<void> _showImage(String source, {String title = ''}) async {
    if (!mounted || !source.startsWith('data:image/')) return;
    try {
      final data = UriData.parse(source);
      final bytes = data.contentAsBytes();
      await Navigator.of(context).push(ReaderImageViewer.route(
          bytes: bytes, svg: data.mimeType == 'image/svg+xml', title: title));
    } catch (e) {
      debugPrint('Could not open illustration: $e');
    }
  }

  void _schedulePagination() {
    _paginationTimer?.cancel();
    _paginationTimer = Timer(const Duration(milliseconds: 200), _measureBook);
  }

  Future<void> _measureBook() async {
    if (!mounted ||
        !_ready ||
        _web == null ||
        _measuring ||
        _pageLayout == null) {
      return;
    }
    final job = ++_paginationJob;
    final layout = _pageLayout;
    _measuring = true;
    try {
      for (var section = 0; section < _spine.length; section++) {
        if (!mounted || job != _paginationJob || !_ready) return;
        if (_sectionPages[section] != null) continue;
        final body = _bodies[section];
        final measured = await _web!.callAsyncJavaScript(
            functionBody: 'return await window.readerMeasure(body);',
            arguments: {'body': body});
        final result = measured?.value;
        if (!mounted || job != _paginationJob) return;
        if (result is! Map ||
            result['valid'] != true ||
            result['layout'] != layout) {
          return;
        }
        setState(() => _sectionPages[section] =
            (result['count'] as num).toInt().clamp(1, 1000000));
      }
    } catch (e) {
      debugPrint('Could not count EPUB pages: $e');
    } finally {
      if (job == _paginationJob) _measuring = false;
    }
  }

  Future<void> _seekBook(int target, {bool preview = false}) async {
    final total = _totalPages;
    if (!_ready || total == null) return;
    var page = target.clamp(0, total - 1);
    for (var section = 0; section < _sectionPages.length; section++) {
      final count = _sectionPages[section]!;
      if (page < count) {
        if (section == _chapter) {
          await _web?.evaluateJavascript(
              source:
                  'window.${preview ? 'readerPreviewPage' : 'readerGoPage'}($page)');
        } else {
          await _openChapter(section, page: page);
        }
        return;
      }
      page -= count;
    }
  }

  Widget _navigation() {
    final total = _totalPages;
    if (total == null) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Preparing book pages…', style: TextStyle(fontSize: 12)));
    }
    return BookSeekSlider(
        total: total,
        page: _bookPage,
        enabled: _ready || _previewing,
        onSeekStart: () {
          _save();
          _previewing = true;
        },
        onPreview: (page) => _seekBook(page, preview: true),
        onSeek: (page) async {
          if (!_previewing) {
            await _seekBook(page);
            return;
          }
          await _seekBook(page, preview: true);
          _previewing = false;
          if (mounted && _ready) await _seekBook(page);
        });
  }

  void _turn(int delta) {
    if (_ready) _web?.evaluateJavascript(source: 'window.readerTurn($delta)');
  }

  Future<void> _fonts() async {
    final selected = await showReaderFontPicker(context, _font);
    if (selected == null || selected.id == _font.id || !mounted || !_ready) {
      return;
    }
    final oldFont = _font, oldCss = _fontCss;
    try {
      final css = await ReaderFonts.loadCss(selected);
      if (!mounted || !_ready) return;
      _paginationJob++;
      _measuring = false;
      setState(() {
        _ready = false;
        _previewing = false;
        _font = selected;
        _fontCss = css;
        _sectionPages = List<int?>.filled(_spine.length, null);
        _pageLayout = null;
      });
      final result = await _web?.callAsyncJavaScript(
        functionBody: 'return await window.readerSetFont(css, id, family);',
        arguments: {'css': css, 'id': selected.id, 'family': selected.family},
      );
      if (result?.error != null) throw StateError('${result!.error}');
      await MyLibraryDb.instance
          .savePreference('pagedReaderFontFamily', selected.id);
    } catch (e) {
      _font = oldFont;
      _fontCss = oldCss;
      try {
        await _web?.callAsyncJavaScript(
          functionBody: 'return await window.readerSetFont(css, id, family);',
          arguments: {
            'css': oldCss,
            'id': oldFont.id,
            'family': oldFont.family
          },
        );
      } catch (_) {
        /* Keep the saved preference unchanged if the WebView closed. */
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not change font. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _ready = true);
        _save();
        _schedulePagination();
      }
    }
  }

  void _changeTextSize(int delta) {
    if (!_ready || _previewing) return;
    final size = (_fontSize + delta).clamp(12, 32).toDouble();
    if (size == _fontSize) return;
    _paginationJob++;
    _measuring = false;
    setState(() {
      _fontSize = size;
      _sectionPages = List<int?>.filled(_spine.length, null);
      _pageLayout = null;
    });
    _web?.evaluateJavascript(
        source: 'window.readerSettings($_fontSize, $_dark)');
    MyLibraryDb.instance.savePreference('pagedReaderFontSize', '$size');
  }

  void _toggleDark() {
    setState(() => _dark = !_dark);
    _web?.evaluateJavascript(
        source: 'window.readerSettings($_fontSize, $_dark)');
    MyLibraryDb.instance.savePreference('pagedReaderDark', _dark ? 1 : 0);
  }

  Future<void> _contents() async {
    final entries = epubContents(_book!, _spine);
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
          child: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
              contentPadding:
                  EdgeInsets.only(left: 16 + 16.0 * entry.depth, right: 16),
              title: Text(entry.title),
              onTap: () => Navigator.pop(context, entry.target));
        },
      )),
    );
    if (selected != null && mounted) _followLink(selected);
  }

  @override
  Widget build(BuildContext context) => BookReaderShell(
        title: _book?.Title ?? widget.fileName,
        subtitle: _currentPart,
        dark: _dark,
        progress: _book == null
            ? ''
            : 'Section ${_chapter + 1}/${_spine.length} · ${_page + 1}/$_count',
        previous:
            _ready && (_chapter > 0 || _page > 0) ? () => _turn(-1) : null,
        next: _ready && (_chapter < _spine.length - 1 || _page < _count - 1)
            ? () => _turn(1)
            : null,
        navigation: _book == null ? null : _navigation(),
        fontSize: _fontSize,
        decreaseText: _ready && !_previewing ? () => _changeTextSize(-1) : null,
        increaseText: _ready && !_previewing ? () => _changeTextSize(1) : null,
        toggleDark: _ready ? _toggleDark : null,
        fonts: _ready && !_previewing ? _fonts : null,
        contents: _ready ? _contents : null,
        onToggleReady: (toggle) => _toggleControls = toggle,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Unable to open EPUB: $_error'))
                : (_readerView ??= InAppWebView(
                    initialData: InAppWebViewInitialData(data: _document()),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: true,
                      javaScriptEnabled: true,
                      disableVerticalScroll: true,
                      disableHorizontalScroll: true,
                      supportZoom: false,
                    ),
                    onWebViewCreated: (controller) {
                      _web = controller;
                      controller.addJavaScriptHandler(
                          handlerName: 'link',
                          callback: (args) {
                            if (args.isNotEmpty && _ready) {
                              _followLink(args.first as String);
                            }
                            return null;
                          });
                      controller.addJavaScriptHandler(
                          handlerName: 'image',
                          callback: (args) {
                            if (args.isNotEmpty && _ready) {
                              _showImage(args.first as String,
                                  title: args.length > 1 && args[1] is String
                                      ? args[1] as String
                                      : '');
                            }
                            return null;
                          });
                      controller.addJavaScriptHandler(
                        handlerName: 'reader',
                        callback: (args) {
                          if (!mounted || args.isEmpty) return null;
                          final value = args.first as Map;
                          if (value['chapter'] != _chapter) return null;
                          setState(() {
                            _page = (value['page'] as num).toInt();
                            _count = (value['count'] as num).toInt();
                            _currentPart =
                                value['partTitle'] as String? ?? _currentPart;
                            if (value['preview'] != true) {
                              _offset = (value['offset'] as num).toInt();
                            }
                          });
                          final layout = value['layout'] as String?;
                          if (layout != null && layout != _pageLayout) {
                            // A new layout invalidates an in-progress slider gesture.
                            if (_pageLayout != null) _previewing = false;
                            _paginationJob++;
                            _measuring = false;
                            _pageLayout = layout;
                            _sectionPages =
                                List<int?>.filled(_spine.length, null);
                          }
                          _sectionPages[_chapter] = _count;
                          _schedulePagination();
                          if (value['preview'] != true) _save();
                          if (!_previewing &&
                              value['preview'] != true &&
                              value['reading'] == true &&
                              !(_chapter == 0 && _page == 0)) {
                            final key = '$_chapter:$_page';
                            _writes = _writes.then((_) async {
                              final changed = await MyLibraryDb.instance
                                  .recordReaderPage(widget.fileName, key);
                              if (changed && mounted) {
                                ref.invalidate(libraryBooksProvider);
                              }
                            }).catchError((Object e) {
                              debugPrint('Could not save reading activity: $e');
                            });
                          }
                          return null;
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'boundary',
                        callback: (args) {
                          _openChapter(
                            _chapter + (args.first as num).toInt(),
                            last: (args.first as num) < 0,
                          );
                          return null;
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'controls',
                        callback: (_) {
                          _toggleControls?.call();
                          return null;
                        },
                      );
                    },
                    onLoadStop: (controller, url) async {
                      if (!mounted) return;
                      await controller.callAsyncJavaScript(
                        functionBody:
                            'await document.fonts.ready; await Promise.all(Array.from(document.images).map(i => i.decode().catch(() => {}))); window.readerRestore($_offset, $_lastPage, $_chapterNavigation); ${_pendingPage == null ? '' : 'window.${_previewing ? 'readerPreviewPage' : 'readerGoPage'}($_pendingPage);'} ${_pendingAnchor == null ? '' : 'window.readerAnchor(${jsonEncode(_pendingAnchor)});'}',
                      );
                      if (mounted) {
                        setState(() {
                          _ready = true;
                          _lastPage = false;
                          _pendingAnchor = null;
                          _pendingPage = null;
                          _chapterNavigation = false;
                          _schedulePagination();
                        });
                        if (_chapterLoaded?.isCompleted == false) {
                          _chapterLoaded!.complete();
                        }
                      }
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame == true && mounted) {
                        setState(() => _error = error.description);
                        if (_chapterLoaded?.isCompleted == false) {
                          _chapterLoaded!.complete();
                        }
                      }
                    },
                  )),
      );
}
