import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/reader_fonts.dart';
import 'package:openlib/ui/components/reader_font_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exactly ten standard fonts and an additional OpenDyslexic option', () {
    expect(ReaderFonts.choices.length, 11);
    expect(ReaderFonts.choices.map((f) => f.id).toSet().length, 11);
    expect(ReaderFonts.choices.last.id, 'opendyslexic');
    expect(ReaderFonts.resolve('missing'), ReaderFonts.bookDefault);
  });
  test('all fonts, style faces and licenses are bundled and usable offline',
      () async {
    final manifest = jsonDecode(
        await rootBundle.loadString('assets/reader_fonts/manifest.json'));
    expect((manifest['fonts'] as List).map((f) => f['id']).toSet(),
        ReaderFonts.choices.map((f) => f.id).toSet());
    for (final font in manifest['fonts']) {
      expect(
          await rootBundle
              .loadString('assets/reader_fonts/${font['id']}-OFL.txt'),
          contains('SIL OPEN FONT LICENSE'));
      for (final face in font['faces']) {
        final bytes = await rootBundle.load(face['asset']);
        expect(ascii.decode(bytes.buffer.asUint8List(0, 4)), 'wOF2');
        expect(bytes.lengthInBytes, greaterThan(10000));
      }
      final css = await ReaderFonts.loadCss(ReaderFonts.resolve(font['id']));
      expect(css, contains('data:font/woff2;base64,'));
      expect(css, contains('font-family:"ReaderFont_${font['id']}"'));
      expect(css, isNot(contains('https:')));
      expect(css, isNot(contains('font-size:')));
    }
    expect(await ReaderFonts.loadCss(ReaderFonts.bookDefault), isEmpty);
  });
  testWidgets(
      'picker marks the current font, can select OpenDyslexic and reset',
      (tester) async {
    ReaderFont selected = ReaderFonts.resolve('literata');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        selected =
                            await showReaderFontPicker(context, selected) ??
                                selected;
                      },
                      child: const Text('Fonts')),
                ))));
    await tester.tap(find.text('Fonts'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Literata'))
            .selected,
        isTrue);
    await tester.scrollUntilVisible(find.text('OpenDyslexic'), 250,
        scrollable: find.byType(Scrollable));
    await tester.ensureVisible(find.text('OpenDyslexic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenDyslexic'));
    await tester.pumpAndSettle();
    expect(selected.id, 'opendyslexic');
    await tester.tap(find.text('Fonts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book default'));
    await tester.pumpAndSettle();
    expect(selected.id, 'default');
  });
}
