import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/book_reader_shell.dart';

void main() {
  testWidgets(
    'controls hide without resizing the page and page arrows stay absent',
    (tester) async {
      VoidCallback? toggle;
      const pageKey = Key('reading-page');
      await tester.pumpWidget(
        MaterialApp(
          home: BookReaderShell(
            title: 'Test book',
            dark: true,
            progress: '2 / 3',
            navigation: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Jump'),
              Slider(value: .5, onChanged: (_) {})
            ]),
            increaseText: () {},
            fonts: () {},
            contents: () {},
            previous: () {},
            next: () {},
            onToggleReady: (callback) => toggle = callback,
            child: const SizedBox.expand(key: pageKey),
          ),
        ),
      );
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Library'), findsNothing);
      expect(find.byTooltip('Contents'), findsNothing);
      expect(find.byTooltip('Increase text size'), findsNothing);
      expect(find.byTooltip('Choose font'), findsNothing);
      final before = tester.getRect(find.byKey(pageKey));
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.text('2 / 3'), findsNothing);
      toggle!();
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      final fontButton = find.byTooltip('Choose font');
      final sizeButton = find.byTooltip('Decrease text size');
      expect(fontButton, findsOneWidget);
      expect(tester.getRect(sizeButton).left - tester.getRect(fontButton).right,
          inInclusiveRange(0, 12));

      expect(DefaultTextStyle.of(tester.element(find.text('Jump'))).style.color,
          const Color(0xffe7dcc7));
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byTooltip('Previous page'), findsNothing);
      toggle!();
      await tester.pump();
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(tester.getRect(find.byKey(pageKey)), before);
      expect(find.text('2 / 3'), findsNothing);
      toggle!();
      await tester.pump();
      expect(find.byTooltip('Previous page'), findsNothing);
    },
  );

  testWidgets('inline size controls and theme toggle need no extra menu',
      (tester) async {
    double size = 12;
    bool dark = true;
    VoidCallback? toggle;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (_, update) => BookReaderShell(
        title: 'Book', progress: 'Section 1/2 · 3/9', dark: dark,
        previous: null, next: null, fontSize: size,
        decreaseText: () => update(() => size--),
        increaseText: () => update(() => size++),
        toggleDark: () => update(() => dark = !dark),
        onToggleReady: (callback) => toggle = callback,
        child: const SizedBox.expand(),
      ),
    )));
    toggle!();
    await tester.pump();
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Decrease text size')).onPressed, isNull);
    await tester.tap(find.byTooltip('Increase text size'));
    await tester.pump();
    expect(size, 13);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byTooltip('Decrease text size'));
    await tester.pump();
    expect(size, 12);
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byTooltip('Increase text size'));
      await tester.pump();
    }
    expect(size, 32);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Increase text size')).onPressed, isNull);
    await tester.tap(find.byTooltip('Use light mode'));
    await tester.pump();
    expect(dark, false);
    expect(find.byTooltip('Use dark mode'), findsOneWidget);
    expect(find.text('Section 1/2 · 3/9'), findsNothing);
    toggle!();
    await tester.pump();
    expect(find.byTooltip('Use dark mode'), findsNothing);
    expect(find.text('A'), findsNothing);
  });

  const longTitle = 'The Changing World Order: Why Nations Succeed and Fail — '
      'Where We Are and Where We Are Going';
  for (final size in [const Size(412, 915), const Size(915, 412)]) {
    testWidgets('the full title wraps centrally above the toolbar at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VoidCallback? toggle;
      var fontsTapped = 0, settingsTapped = 0;
      await tester.pumpWidget(MaterialApp(
          home: BookReaderShell(
        title: longTitle,
        progress: '2 / 10',
        previous: () {},
        next: () {},
        fonts: () => fontsTapped++,
        increaseText: () => settingsTapped++,
        contents: () {},
        onToggleReady: (callback) => toggle = callback,
        child: const SizedBox.expand(key: Key('page')),
      )));
      final pageBefore = tester.getRect(find.byKey(const Key('page')));
      expect(find.text(longTitle), findsNothing);
      toggle!();
      await tester.pump();
      final title = find.text(longTitle);
      final text = tester.widget<Text>(title);
      expect(text.textAlign, TextAlign.center);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.getRect(title).center.dx, closeTo(size.width / 2, .1));
      final paragraph = tester.renderObject<RenderParagraph>(title);
      final lines = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: longTitle.length));
      expect(lines.length, greaterThan(1));
      final titleViewport = tester.getRect(find.byType(SingleChildScrollView));
      for (final box in lines) {
        final top = paragraph.localToGlobal(Offset(box.left, box.top));
        final bottom = paragraph.localToGlobal(Offset(box.right, box.bottom));
        expect(top.dy, greaterThanOrEqualTo(titleViewport.top));
        expect(bottom.dy, lessThanOrEqualTo(titleViewport.bottom + 1));
      }
      for (final tooltip in [
        'Library',
        'Contents',
        'Choose font',
        'Increase text size'
      ]) {
        expect(tester.getRect(find.byTooltip(tooltip)).top,
            greaterThanOrEqualTo(titleViewport.bottom));
      }
      await tester.tap(find.byTooltip('Choose font'));
      await tester.tap(find.byTooltip('Increase text size'));
      expect(fontsTapped, 1);
      expect(settingsTapped, 1);
      toggle!();
      await tester.pump();
      expect(find.text(longTitle), findsNothing);
      expect(tester.getRect(find.byKey(const Key('page'))), pageBefore);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'very long titles and large text stay readable without hiding toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    VoidCallback? toggle;
    final title = List.filled(6, longTitle).join(' ');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 640), textScaler: TextScaler.linear(2)),
      child: BookReaderShell(
          title: title,
          progress: '',
          previous: () {},
          next: () {},
          fonts: () {},
          increaseText: () {},
          contents: () {},
          onToggleReady: (callback) => toggle = callback,
          child: const SizedBox.expand()),
    )));
    toggle!();
    await tester.pump();
    final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable));
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.maxScrollExtent, greaterThan(0));
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump();
    expect(state.position.pixels, state.position.maxScrollExtent);
    expect(find.byTooltip('Choose font').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Increase text size').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'library arrow stays at the left edge and current part sits under the centred book title',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    VoidCallback? toggle;
    Widget shell(String part) => MaterialApp(
            home: BookReaderShell(
          title: 'The Changing World Order',
          subtitle: part,
          progress: '2 / 10',
          previous: () {},
          next: () {},
          fonts: () {},
          increaseText: () {},
          contents: () {},
          onToggleReady: (callback) => toggle = callback,
          child: const SizedBox.expand(key: Key('reading-page')),
        ));
    await tester.pumpWidget(shell('Chapter 2: Money and credit'));
    final pageBefore = tester.getRect(find.byKey(const Key('reading-page')));
    expect(find.text('Chapter 2: Money and credit'), findsNothing);
    toggle!();
    await tester.pump();
    final title = find.text('The Changing World Order');
    final part = find.text('Chapter 2: Money and credit');
    expect(tester.getRect(title).center.dx, closeTo(206, .1));
    expect(tester.getRect(part).center.dx, closeTo(206, .1));
    expect(tester.getRect(part).top, greaterThan(tester.getRect(title).bottom));
    expect(tester.widget<Text>(part).style!.fontSize,
        lessThan(tester.widget<Text>(title).style!.fontSize!));
    expect(tester.getRect(find.byTooltip('Library')).left, lessThan(32));
    final actions = tester
        .getRect(find.byTooltip('Contents'))
        .expandToInclude(tester.getRect(find.byTooltip('Increase text size')));
    expect(actions.center.dx, closeTo(206, .1));
    expect(tester.getRect(find.byTooltip('Library')).left,
        lessThan(tester.getRect(find.byTooltip('Contents')).left));
    expect(tester.getRect(find.byTooltip('Choose font')).top,
        greaterThan(tester.getRect(part).bottom));
    await tester.pumpWidget(shell('The Fundamentals'));
    await tester.pump();
    expect(find.text('Chapter 2: Money and credit'), findsNothing);
    expect(find.text('The Fundamentals'), findsOneWidget);
    toggle!();
    await tester.pump();
    expect(find.text('The Fundamentals'), findsNothing);
    expect(tester.getRect(find.byKey(const Key('reading-page'))), pageBefore);
  });
}
