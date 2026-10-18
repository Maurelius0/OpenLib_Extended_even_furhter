import 'dart:convert';
import 'package:flutter/services.dart';

class ReaderFont {
  const ReaderFont(this.id, this.name, this.kind);
  final String id, name, kind;
  String get family => id == 'default' ? '' : 'ReaderFont_$id';
}

/// Only the selected font is embedded in the reading document. All assets are
/// bundled; neither the picker nor the reader contacts a font service.
class ReaderFonts {
  static const bookDefault =
      ReaderFont('default', 'Book default', 'Original styling');
  static const choices = [
    ReaderFont('literata', 'Literata', 'Serif'),
    ReaderFont('lora', 'Lora', 'Serif'),
    ReaderFont('librebaskerville', 'Libre Baskerville', 'Serif'),
    ReaderFont('sourceserif4', 'Source Serif 4', 'Serif'),
    ReaderFont('ebgaramond', 'EB Garamond', 'Serif'),
    ReaderFont('notoserif', 'Noto Serif', 'Serif'),
    ReaderFont('sourcesans3', 'Source Sans 3', 'Sans serif'),
    ReaderFont('nunito', 'Nunito', 'Rounded sans serif'),
    ReaderFont('atkinsonhyperlegible', 'Atkinson Hyperlegible', 'Sans serif'),
    ReaderFont('lexend', 'Lexend', 'Sans serif'),
    ReaderFont('opendyslexic', 'OpenDyslexic', 'Dyslexia-oriented'),
  ];

  static ReaderFont resolve(Object? id) =>
      choices.firstWhere((font) => font.id == id, orElse: () => bookDefault);

  static Future<String> loadCss(ReaderFont font) async {
    if (font.id == 'default') return '';
    final manifest = jsonDecode(
            await rootBundle.loadString('assets/reader_fonts/manifest.json'))
        as Map<String, dynamic>;
    final entry = (manifest['fonts'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((entry) => entry['id'] == font.id);
    final css = StringBuffer();
    for (final face in entry['faces'] as List) {
      final data = await rootBundle.load(face['asset'] as String);
      final encoded = base64Encode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      css.write('@font-face{font-family:"${font.family}";'
          'src:url(data:font/woff2;base64,$encoded) format("woff2");'
          'font-weight:${face['weight']};font-style:${face['style']};'
          'font-display:block;}');
    }
    return css.toString();
  }
}
