import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlib/services/reader_screen_timeout.dart';

/// Controls overlay the page; opening them never resizes or repaginates it.
class BookReaderShell extends StatefulWidget {
  const BookReaderShell({
    super.key,
    required this.title,
    required this.progress,
    required this.child,
    required this.previous,
    required this.next,
    this.subtitle,
    this.fontSize = 20,
    this.decreaseText,
    this.increaseText,
    this.toggleDark,
    this.fonts,
    this.contents,
    this.onToggleReady,
    this.dark,
    this.navigation,
  });
  final String title, progress;
  final String? subtitle;
  final double fontSize;
  final bool? dark;
  final Widget child;
  final Widget? navigation;
  final VoidCallback? previous,
      next,
      decreaseText,
      increaseText,
      toggleDark,
      contents,
      fonts;
  final void Function(VoidCallback toggle)? onToggleReady;
  @override
  State<BookReaderShell> createState() => _BookReaderShellState();
}

class _BookReaderShellState extends State<BookReaderShell> {
  bool _controls = false;
  void _toggle() {
    if (mounted) setState(() => _controls = !_controls);
  }

  @override
  void initState() {
    super.initState();
    widget.onToggleReady?.call(_toggle);
    unawaited(ReaderScreenTimeout.setReading(true));
  }

  @override
  void dispose() {
    unawaited(ReaderScreenTimeout.setReading(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark ?? Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xff211e1a) : const Color(0xfff6efdf);
    final ink = dark ? const Color(0xffe7dcc7) : const Color(0xff30291f);
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: LayoutBuilder(
            builder: (context, bounds) => Stack(children: [
                  Positioned.fill(child: widget.child),
                  if (_controls)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: bounds.maxHeight * .45),
                        child: Material(
                          color: paper,
                          elevation: 0,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(18)),
                          clipBehavior: Clip.antiAlias,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                                child: SingleChildScrollView(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 8, 24, 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(widget.title,
                                            textAlign: TextAlign.center,
                                            softWrap: true,
                                            style: TextStyle(
                                                fontSize: 15,
                                                height: 1.3,
                                                fontWeight: FontWeight.w500,
                                                color: ink)),
                                        if (widget.subtitle
                                                ?.trim()
                                                .isNotEmpty ==
                                            true) ...[
                                          const SizedBox(height: 4),
                                          Text(widget.subtitle!.trim(),
                                              textAlign: TextAlign.center,
                                              softWrap: true,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.35,
                                                  color: ink.withValues(
                                                      alpha: .7))),
                                        ],
                                      ]),
                                ),
                              ),
                            )),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Divider(
                                    height: 1,
                                    thickness: .5,
                                    color: ink.withValues(alpha: .14))),
                            IconButtonTheme(
                                data: IconButtonThemeData(
                                    style: IconButton.styleFrom(
                                  foregroundColor: ink,
                                  disabledForegroundColor:
                                      ink.withValues(alpha: .25),
                                  minimumSize: const Size(44, 48),
                                  padding: const EdgeInsets.all(8),
                                )),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  child: Row(children: [
                                    IconButton(
                                        tooltip: 'Library',
                                        icon: const Icon(
                                            Icons.arrow_back_ios_new,
                                            size: 20),
                                        onPressed: () =>
                                            Navigator.of(context).pop()),
                                    Expanded(
                                        child: Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (widget.contents != null)
                                          IconButton(
                                              tooltip: 'Contents',
                                              onPressed: widget.contents,
                                              icon: const Icon(Icons.list,
                                                  size: 23)),
                                        if (widget.fonts != null)
                                          IconButton(
                                              tooltip: 'Choose font',
                                              onPressed: widget.fonts,
                                              icon: const Icon(
                                                  Icons.font_download_outlined,
                                                  size: 21)),
                                        if (widget.decreaseText != null ||
                                            widget.increaseText != null)
                                          Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                    tooltip:
                                                        'Decrease text size',
                                                    onPressed: widget.fontSize >
                                                            12
                                                        ? widget.decreaseText
                                                        : null,
                                                    icon: const Icon(
                                                        Icons.remove,
                                                        size: 20)),
                                                Semantics(
                                                    label:
                                                        'Text size ${widget.fontSize.round()}',
                                                    child: ExcludeSemantics(
                                                        child: Text('A',
                                                            style: TextStyle(
                                                                fontSize: 21,
                                                                color: ink)))),
                                                IconButton(
                                                    tooltip:
                                                        'Increase text size',
                                                    onPressed: widget.fontSize <
                                                            32
                                                        ? widget.increaseText
                                                        : null,
                                                    icon: const Icon(Icons.add,
                                                        size: 20)),
                                              ]),
                                      ],
                                    )),
                                    if (widget.toggleDark != null)
                                      IconButton(
                                          tooltip: dark
                                              ? 'Use light mode'
                                              : 'Use dark mode',
                                          isSelected: dark,
                                          onPressed: widget.toggleDark,
                                          icon: const Icon(
                                              Icons.dark_mode_outlined,
                                              size: 22),
                                          selectedIcon: const Icon(
                                              Icons.light_mode_outlined,
                                              size: 22))
                                    else
                                      const SizedBox(width: 48),
                                  ]),
                                )),
                          ]),
                        ),
                      ),
                    ),
                  if (_controls && widget.navigation != null)
                    Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Material(
                            color: paper,
                            child: DefaultTextStyle.merge(
                                style: TextStyle(color: ink),
                                child: widget.navigation!))),
                ])),
      ),
    );
  }
}
