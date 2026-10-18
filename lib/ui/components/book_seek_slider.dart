import 'dart:async';
import 'package:flutter/material.dart';

/// One preview in flight; rapid motion replaces queued destinations.
class BookSeekSlider extends StatefulWidget {
  const BookSeekSlider(
      {super.key,
      required this.total,
      required this.page,
      required this.enabled,
      required this.onSeek,
      this.onPreview,
      this.onSeekStart});
  final int total, page;
  final bool enabled;
  final FutureOr<void> Function(int) onSeek;
  final FutureOr<void> Function(int)? onPreview;
  final VoidCallback? onSeekStart;
  @override
  State<BookSeekSlider> createState() => _BookSeekSliderState();
}

class _BookSeekSliderState extends State<BookSeekSlider> {
  double? _draft;
  Timer? _timer;
  int? _pending, _finalTarget;
  bool _busy = false, _ending = false;
  void _start() {
    widget.onSeekStart?.call();
  }

  void _move(double value) {
    setState(() => _draft = value);
    if (widget.onPreview == null) return;
    _pending = value.round();
    _timer ??= Timer(const Duration(milliseconds: 140), () {
      _timer = null;
      _preview();
    });
  }

  Future<void> _preview() async {
    if (_busy || !mounted || _pending == null) return;
    final target = _pending!;
    _pending = null;
    _busy = true;
    try {
      await widget.onPreview?.call(target);
    } catch (e) {
      debugPrint('Page preview unavailable: $e');
    } finally {
      _busy = false;
      if (mounted) {
        if (_ending) {
          await _commit();
        } else if (_pending != null) {
          _timer ??= Timer(const Duration(milliseconds: 140), () {
            _timer = null;
            _preview();
          });
        }
      }
    }
  }

  Future<void> _end(double value) async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _ending = true;
    _finalTarget = value.round();
    if (!_busy) await _commit();
  }

  Future<void> _commit() async {
    if (_finalTarget == null) return;
    final target = _finalTarget!;
    _finalTarget = null;
    try {
      await widget.onSeek(target);
    } finally {
      if (mounted) {
        setState(() {
          _draft = null;
          _ending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = (_draft ?? widget.page.toDouble())
        .clamp(0, widget.total - 1)
        .toDouble();
    final ink = DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    final paper = context.findAncestorWidgetOfExactType<Material>()?.color ??
        Theme.of(context).scaffoldBackgroundColor;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ExcludeSemantics(
                child: Text(
              '${value.round() + 1}/${widget.total}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.2, color: ink.withValues(alpha: .8)),
            )),
          ),
          SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: ink.withValues(alpha: .75),
                inactiveTrackColor: ink.withValues(alpha: .18),
                thumbColor: ink,
                thumbShape: ReaderSliderThumb(outlineColor: paper),
                overlayShape: SliderComponentShape.noOverlay,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: SizedBox(
                height: 48,
                child: Slider(
                    value: value,
                    min: 0,
                    max: (widget.total - 1).clamp(1, 100000000).toDouble(),
                    label: 'Page ${value.round() + 1}',
                    semanticFormatterCallback: (v) =>
                        'Page ${v.round() + 1} of ${widget.total}',
                    onChangeStart: (_) => _start(),
                    onChanged: widget.enabled && !_ending && widget.total > 1
                        ? _move
                        : null,
                    onChangeEnd: _end),
              )),
        ]));
  }
}

/// A small visual handle with the slider's full accessible touch target.
class ReaderSliderThumb extends SliderComponentShape {
  const ReaderSliderThumb({required this.outlineColor});
  final Color outlineColor;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 10);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = Color.lerp(sliderTheme.disabledThumbColor,
        sliderTheme.thumbColor, enableAnimation.value)!;
    final handle = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 24, height: 8),
        const Radius.circular(3));
    context.canvas.drawRRect(handle, Paint()..color = color);
    context.canvas.drawRRect(
        handle.deflate(1.5),
        Paint()
          ..color = outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = .75);
  }
}
