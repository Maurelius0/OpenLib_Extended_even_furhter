import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/reader_image_viewer.dart';

Future<void> openImage(WidgetTester tester, {String title = ''}) async {
  final bytes = Uint8List.fromList(utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="red"/></svg>'));
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      ReaderImageViewer.route(
                          bytes: bytes, svg: true, title: title)),
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
