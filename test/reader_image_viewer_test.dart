import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/reader_image_viewer.dart';

Future<void> openImage(WidgetTester tester,
    {String title = '',
    bool svg = true,
    Uint8List? imageBytes,
    bool reducedMotion = false}) async {
  final bytes = imageBytes ??
      Uint8List.fromList(utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="red"/></svg>'));
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      ReaderImageViewer.route(
                          bytes: bytes, svg: svg, title: title)),
                  child: const Text('Book page'))))));
  await tester.tap(find.text('Book page'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'illustration viewer keeps zoom without generic title, back arrow or reset button',
      (tester) async {
    await openImage(tester);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.diagonal3Values(3, 3, 1);
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 3);
    expect(find.text('Image'), findsNothing);
    expect(find.text('Reset zoom'), findsNothing);
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 8);
    expect(find.byType(BackButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Book page'), findsOneWidget);
  });

  Future<void> doubleTap(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pump();
  }

  testWidgets('double tap zooms around the tapped point and returns to fit',
      (tester) async {
    await openImage(tester, title: 'Diagram title');
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    final bounds = tester.getRect(viewer);
    const local = Offset(90, 120);
    final point = bounds.topLeft + local;
    await doubleTap(tester, point);
    await tester.pump(const Duration(milliseconds: 80));
    final midScale = controller.value.getMaxScaleOnAxis();
    expect(midScale, greaterThan(1));
    expect(midScale, lessThan(2.5));
    expect(
        (MatrixUtils.transformPoint(controller.value, local) - local).distance,
        lessThan(.01));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, .01));
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    await doubleTap(tester, bounds.center);
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
    expect(controller.value.getTranslation().length, closeTo(0, .01));
    await tester.drag(viewer, const Offset(0, 55));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });

  testWidgets('double tap resets a panned zoom and zoomed dragging stays open',
      (tester) async {
    await openImage(tester);
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    controller.value = Matrix4.diagonal3Values(3, 3, 1)
      ..setTranslationRaw(-300, -300, 0);
    await tester.pump();
    await doubleTap(tester, tester.getCenter(viewer));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
    await doubleTap(tester, tester.getCenter(viewer));
    await tester.pumpAndSettle();
    final before = controller.value.getTranslation().y;
    await tester.drag(viewer, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    expect(controller.value.getTranslation().y, greaterThan(before));
  });

  testWidgets('touch interrupts zoom animation and system back is safe',
      (tester) async {
    await openImage(tester);
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await doubleTap(tester, tester.getCenter(viewer));
    await tester.pump(const Duration(milliseconds: 60));
    final gesture = await tester.startGesture(tester.getCenter(viewer));
    final stopped = controller.value.clone();
    await tester.pump(const Duration(milliseconds: 240));
    expect(controller.value, stopped);
    await gesture.up();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raster double tap respects reduced motion', (tester) async {
    await openImage(tester,
        svg: false,
        reducedMotion: true,
        imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=='));
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await doubleTap(tester, tester.getCenter(viewer));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, .01));
    await tester.pumpAndSettle();
    await doubleTap(tester, tester.getCenter(viewer));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping down closes the image and returns to the book',
      (tester) async {
    await openImage(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(find.text('Book page'), findsOneWidget);
  });

  testWidgets('a short downward swipe fades and slides, then finishes itself',
      (tester) async {
    await openImage(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 55));
    await tester.pump();
    final opacity = find.descendant(
        of: find.byType(ReaderImageViewer), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
    final transform = find
        .descendant(
            of: find.byType(ReaderImageViewer),
            matching: find.byType(Transform))
        .first;
    expect(
        tester.widget<Transform>(transform).transform.getTranslation().y, 55);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(tester.widget<Transform>(transform).transform.getTranslation().y,
        greaterThan(55));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(find.text('Book page'), findsOneWidget);
  });

  testWidgets('system back during the exit animation cancels it safely',
      (tester) async {
    await openImage(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 55));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short, upward and horizontal drags leave the image open',
      (tester) async {
    await openImage(tester);
    for (final delta in [
      const Offset(0, 35),
      const Offset(0, -160),
      const Offset(160, 0),
      const Offset(160, 100),
    ]) {
      await tester.drag(find.byType(InteractiveViewer), delta);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderImageViewer), findsOneWidget);
    }
  });

  testWidgets('a zoomed image pans down without closing', (tester) async {
    await openImage(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.diagonal3Values(3, 3, 1)
      ..setTranslationRaw(-400, -400, 0);
    await tester.pump();
    final before = controller.value.getTranslation().y;
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    expect(controller.value.getTranslation().y, greaterThan(before));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(3, 0.01));

    // Once fitted again, a new downward swipe can dismiss normally.
    controller.value = Matrix4.identity();
    await tester.pump();
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });

  testWidgets('two finger downward movement and pinch never dismiss the image',
      (tester) async {
    await openImage(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left =
        await tester.startGesture(center - const Offset(50, 0), pointer: 1);
    final right =
        await tester.startGesture(center + const Offset(50, 0), pointer: 2);
    await tester.pump();
    await left.moveBy(const Offset(-35, 80));
    await right.moveBy(const Offset(35, 80));
    await tester.pump();
    await left.moveBy(const Offset(0, 80));
    await right.moveBy(const Offset(0, 80));
    await tester.pump();
    await right.up();
    await left.up();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
  });

  testWidgets('adding a second finger cancels dismissal until all fingers lift',
      (tester) async {
    await openImage(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first =
        await tester.startGesture(center - const Offset(40, 120), pointer: 1);
    await first.moveBy(const Offset(0, 120));
    await tester.pump();
    final second =
        await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await tester.pump();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    await second.up();
    await first.moveBy(const Offset(0, 140));
    await first.up();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });

  testWidgets('a cancelled swipe stays open and the next swipe works',
      (tester) async {
    await openImage(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 160));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });

  testWidgets(
      'a pinch attempt without further movement does not block the next swipe',
      (tester) async {
    await openImage(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first =
        await tester.startGesture(center - const Offset(40, 120), pointer: 1);
    await first.moveBy(const Offset(0, 120));
    await tester.pump();
    final second =
        await tester.startGesture(center + const Offset(40, 0), pointer: 2);
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsOneWidget);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });

  testWidgets(
      'a supplied image title appears without a back arrow and swipe still closes',
      (tester) async {
    await openImage(tester, title: 'The long-term debt cycle');
    expect(find.text('The long-term debt cycle'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Image'), findsNothing);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(find.text('Book page'), findsOneWidget);
  });
}
