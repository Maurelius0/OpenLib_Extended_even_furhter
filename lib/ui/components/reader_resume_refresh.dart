import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Refresh the retained native page after the window becomes visible again.
/// A normal rebuild can reuse the same platform-view layer without painting it.
class ReaderResumeRefresh extends StatefulWidget {
  const ReaderResumeRefresh({
    super.key,
    required this.child,
    required this.onResume,
  });

  final Widget child;
  final Future<void> Function() onResume;

  @override
  State<ReaderResumeRefresh> createState() => _ReaderResumeRefreshState();
}

class _ReaderResumeRefreshState extends State<ReaderResumeRefresh>
    with WidgetsBindingObserver {
  final _paintKey = GlobalKey();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final generation = ++_generation;
    if (state != AppLifecycleState.resumed) return;
    // Wait until the unlocked window has its final dimensions and surface.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        unawaited(_refresh(generation));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _refresh(int generation) async {
    try {
      await widget.onResume();
    } catch (error) {
      debugPrint('Could not refresh resumed reader: $error');
    } finally {
      if (mounted && generation == _generation) {
        final boundary = _paintKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary) boundary.markNeedsPaint();
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _paintKey, child: widget.child);
}
