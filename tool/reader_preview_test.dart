// Render the actual reader controls with representative text, not a mockup.
// READER_PREVIEW_DIR=/absolute/path flutter test --no-pub tool/reader_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/book_reader_shell.dart';
import 'package:openlib/ui/components/book_seek_slider.dart';
import 'package:openlib/ui/components/reader_image_viewer.dart';

const previewKey = Key('capture');
final readerKey = GlobalKey<_PreviewReaderState>();
const sample = 'Money makes it possible to exchange the work we do today for '
    'the things we need tomorrow. It connects people who may never meet, '
    'allowing them to trade through a shared understanding of value.\n\n'
    'Across history, communities have used many different forms of money. '
    'The materials have changed, but trust has remained central to every system.\n\n'
    'To understand money, it helps to look beyond the coins and notes in our '
    'hands and consider the promises, institutions, and relationships behind them.';

class _PreviewReader extends StatefulWidget {
  const _PreviewReader({super.key});
  @override
  State<_PreviewReader> createState() => _PreviewReaderState();
}

class _PreviewReaderState extends State<_PreviewReader> {
  bool dark = true;
  double size = 20;
  VoidCallback? toggle;
  void image() => Navigator.of(context).push(ReaderImageViewer.route(
      svg: true,
      title: 'An illustration of change over time',
      bytes: Uint8List.fromList(utf8.encode(
          '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 260">
    <rect x="0" y="0" width="360" height="260" rx="12" fill="#f6efdf"/>
    <path d="M35 30V220H330" fill="none" stroke="#756a59" stroke-width="2"/>
    <path d="M35 190 Q80 60 120 150 T210 105 T330 40" fill="none" stroke="#a56843" stroke-width="4"/>
    <path d="M35 170 Q110 210 165 100 T270 130 T330 70" fill="none" stroke="#747e67" stroke-width="3"/>
    </svg>'''))));
  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xffe7dcc7) : const Color(0xff30291f);
    return BookReaderShell(
      title: "The Changing World Order: Where we are and where we're going",
      subtitle: 'Chapter 2 · What Is Money?',
      progress: 'Section 2/12 · 8/34',
      dark: dark,
      previous: () {},
      next: () {},
      contents: () {},
      fonts: () {},
      fontSize: size,
      decreaseText: () => setState(() => size = (size - 1).clamp(12, 32)),
      increaseText: () => setState(() => size = (size + 1).clamp(12, 32)),
      toggleDark: () => setState(() => dark = !dark),
      onToggleReady: (callback) => toggle = callback,
      navigation:
          BookSeekSlider(total: 428, page: 119, enabled: true, onSeek: (_) {}),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 180, 28, 80),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('What Is Money?',
                style: TextStyle(
                    fontFamily: 'BookSerif',
                    fontSize: 27,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: ink)),
            const SizedBox(height: 24),
            Text(sample,
                maxLines: 15,
                overflow: TextOverflow.clip,
                style: TextStyle(
                    fontFamily: 'BookSerif',
                    fontSize: size,
                    height: 1.65,
                    color: ink)),
          ])),
    );
  }
}

void main() {
  testWidgets('export reader design and short swipe animation', (tester) async {
    final dir = Directory(Platform.environment['READER_PREVIEW_DIR']!);
    dir.createSync(recursive: true);
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final name in ['Nunito', 'BookSerif']) {
      final font = FontLoader(name)
        ..addFont(Future.value(ByteData.sublistView(
            File('${dir.parent.path}/toolchain/preview-fonts/$name.ttf')
                .readAsBytesSync())));
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester.pumpWidget(RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: 'Nunito',
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xffa56843))),
            home: _PreviewReader(key: readerKey))));
    await tester.pumpAndSettle();
    readerKey.currentState!.toggle!();
    await tester.pumpAndSettle();
    Future<void> capture(String name, {double ratio = 2}) async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${dir.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('Reader-Menu-Dark');
    await tester.tap(find.byTooltip('Use light mode'));
    await tester.pumpAndSettle();
    await capture('Reader-Menu-Light');
    await tester.tap(find.byTooltip('Use dark mode'));
    await tester.pumpAndSettle();
    readerKey.currentState!.toggle!();
    await tester.pumpAndSettle();
    readerKey.currentState!.image();
    await tester.pumpAndSettle();
    for (int i = 0; i < 5; i++) {
      await capture('swipe-${i.toString().padLeft(2, '0')}', ratio: 1);
    }
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(InteractiveViewer)));
    for (int i = 1; i <= 5; i++) {
      await gesture.moveBy(const Offset(0, 11));
      await tester.pump(const Duration(milliseconds: 30));
      await capture('swipe-${(i + 4).toString().padLeft(2, '0')}', ratio: 1);
    }
    await gesture.up();
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      await capture('swipe-${(i + 10).toString().padLeft(2, '0')}', ratio: 1);
    }
    await tester.pumpAndSettle();
    await capture('swipe-18', ratio: 1);
    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: Platform.environment['READER_PREVIEW_DIR'] == null);
}
