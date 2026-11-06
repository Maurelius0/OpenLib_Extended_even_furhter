import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The reader's indeterminate loading indicator.
class BookLoadingIndicator extends StatefulWidget {
  const BookLoadingIndicator({super.key, this.color, this.backgroundColor});

  final Color? color;
  final Color? backgroundColor;

  @override
  State<BookLoadingIndicator> createState() => _BookLoadingIndicatorState();
}

class _BookLoadingIndicatorState extends State<BookLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 0;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(88, 68),
          painter: _BookPainter(
            _animation,
            widget.color ?? theme.colorScheme.onSurface,
            widget.backgroundColor ?? theme.scaffoldBackgroundColor,
          ),
        ),
      ),
    );
  }
}

class _BookPainter extends CustomPainter {
  _BookPainter(this.animation, this.ink, this.paper)
      : super(repaint: animation);

  final Animation<double> animation;
  final Color ink;
  final Color paper;

  static const _skew = 0.17632698;
  static const _turn = Cubic(0.42, 0, 0.58, 1);
  static const _segments = [0.12, 0.48, 0.84];

  static Path _page(double projection, {double dx = 0, double dy = 0}) {
    final x = 38 * projection;
    return Path()
      ..moveTo(38 + dx, 4 + dy - dx.abs() * _skew)
      ..relativeLineTo(x, -38 * _skew)
      ..relativeLineTo(0, 48)
      ..relativeLineTo(-x, 38 * _skew)
      ..close();
  }

  static Path _edge(double side, double outer, double inner) => Path.combine(
        PathOperation.difference,
        _page(side, dx: side * outer, dy: outer),
        _page(side, dx: side * inner, dy: inner),
      );

  static final _pages = [_page(-1), _page(1)];
  static final _innerEdges = [_edge(-1, 3, 2), _edge(1, 3, 2)];
  static final _coverEdges = [
    for (final side in [-1.0, 1.0])
      Path.combine(
        PathOperation.difference,
        _edge(side, 6.25, 5),
        Path()
          ..moveTo(38 + side * 7, 55.65)
          ..lineTo(38 + side * 5.75, 55.65)
          ..lineTo(38 + side * 5.75, 56.8)
          ..close(),
      ),
  ];
  static final _fixedPaths = [..._coverEdges, ..._innerEdges, ..._pages];
  static final _binding = Path()
    ..moveTo(31, 56)
    ..quadraticBezierTo(38, 59, 45, 56)
    ..lineTo(45, 57.25)
    ..quadraticBezierTo(38, 60.25, 31, 57.25)
    ..close();

  void _text(Canvas canvas, double projection, Paint paint) {
    for (var row = 0; row < 4; row++) {
      final y = 16.5 + row * 7;
      canvas.drawLine(
        Offset(38 + 8.5 * projection, y - 8.5 * _skew),
        Offset(38 + 29.5 * projection, y - 29.5 * _skew),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 88, size.height / 68);
    final phase = animation.value;
    final turnTime = (phase * 2) % 1;
    final firstHalf = turnTime <= _segments[1];
    final start = firstHalf ? _segments[0] : _segments[1];
    final end = firstHalf ? _segments[1] : _segments[2];
    final progress = ((turnTime - start) / (end - start)).clamp(0.0, 1.0);
    final angle =
        (firstHalf ? 0 : math.pi / 2) + _turn.transform(progress) * math.pi / 2;
    final projection = math.cos(angle);
    final creaseOpacity =
        0.75 * _turn.transform(((turnTime - 0.5).abs() / 0.32).clamp(0.0, 1.0));

    canvas.save();
    canvas.translate(
      (size.width - 76 * scale) / 2,
      (size.height - 56 * scale) / 2 +
          4 * math.cos(phase * 2 * math.pi) * scale,
    );
    canvas.scale(scale);
    final inkPaint = Paint()..color = ink;
    final textPaint = Paint()
      ..color = paper
      ..strokeWidth = 1.5;

    for (final path in _fixedPaths) {
      canvas.drawPath(path, inkPaint);
    }
    _text(canvas, -1, textPaint);
    _text(canvas, 1, textPaint);
    canvas.drawPath(_page(projection), inkPaint);
    if (projection.abs() > 0.01) _text(canvas, projection, textPaint);
    canvas.drawPath(_binding, inkPaint);
    canvas.drawLine(
      const Offset(38, 5),
      const Offset(38, 51),
      textPaint
        ..strokeWidth = 1
        ..color = paper.withValues(alpha: creaseOpacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookPainter oldDelegate) =>
      ink != oldDelegate.ink || paper != oldDelegate.paper;
}
