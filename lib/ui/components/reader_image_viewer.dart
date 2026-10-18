import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ReaderImageViewer extends StatefulWidget {
  const ReaderImageViewer(
      {super.key, required this.bytes, required this.svg, this.title = ''});
  final Uint8List bytes;
  final bool svg;
  final String title;

  static PageRoute<void> route(
          {required Uint8List bytes, required bool svg, String title = ''}) =>
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) =>
            ReaderImageViewer(bytes: bytes, svg: svg, title: title),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  State<ReaderImageViewer> createState() => _ReaderImageViewerState();
}

class _ReaderImageViewerState extends State<ReaderImageViewer>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController.unbounded(vsync: this);
  bool _closing = false;
  final _transform = TransformationController();
  int _pointerCount = 0;
  Offset _dragStart = Offset.zero;
  Offset _dragDistance = Offset.zero;
  bool _canDismiss = false;

  // Observe touches without competing with InteractiveViewer's pinch/pan
  // recognizer. A second finger cancels dismissal for the whole interaction.
  void _onPointerDown(PointerDownEvent event) {
    if (_closing) return;
    _pointerCount++;
    if (_pointerCount == 1) {
      _slide.stop();
      _slide.value = 0;
      _dragStart = event.position;
      _dragDistance = Offset.zero;
      _canDismiss = _transform.value.getMaxScaleOnAxis() <= 1.01;
    } else {
      _canDismiss = false;
      _returnToPlace();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_closing || !_canDismiss) return;
    _dragDistance = event.position - _dragStart;
    final downward =
        _dragDistance.dy > 0 && _dragDistance.dy > _dragDistance.dx.abs() * 1.5;
    _slide.value = downward ? _dragDistance.dy : 0;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_closing) return;
    _pointerCount--;
    if (_pointerCount != 0) return;
    final dismiss = _canDismiss &&
        _transform.value.getMaxScaleOnAxis() <= 1.01 &&
        _dragDistance.dy >= 48 &&
        _dragDistance.dy > _dragDistance.dx.abs() * 1.5;
    _canDismiss = false;
    if (dismiss && ModalRoute.of(context)?.isCurrent == true) {
      _dismiss();
    } else {
      _returnToPlace();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerCount--;
    _canDismiss = false;
    _returnToPlace();
  }

  void _returnToPlace() {
    if (_slide.value != 0 && !_closing) {
      _slide.animateTo(0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic);
    }
  }

  Future<void> _dismiss() async {
    _closing = true;
    try {
      await _slide
          .animateTo(MediaQuery.sizeOf(context).height,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInCubic)
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      final closed = await Navigator.of(context).maybePop();
      if (!closed && mounted) {
        _closing = false;
        _returnToPlace();
      }
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: AnimatedBuilder(
          animation: _slide,
          child: _imageScaffold(),
          builder: (context, child) {
            final progress =
                (_slide.value / (MediaQuery.sizeOf(context).height * .65))
                    .clamp(0.0, 1.0);
            return Stack(fit: StackFit.expand, children: [
              ColoredBox(color: Colors.black.withValues(alpha: 1 - progress)),
              Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: Opacity(opacity: 1 - progress, child: child)),
            ]);
          },
        ),
      );

  Widget _imageScaffold() => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: widget.title.trim().isEmpty
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                centerTitle: true,
                toolbarHeight: 80,
                title: Text(widget.title.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
              ),
        body: SafeArea(
            child: LayoutBuilder(
                builder: (context, constraints) => InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 8,
                      child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: widget.svg
                              ? SvgPicture.memory(widget.bytes,
                                  fit: BoxFit.contain)
                              : Image.memory(widget.bytes,
                                  fit: BoxFit.contain)),
                    ))),
      );
}
