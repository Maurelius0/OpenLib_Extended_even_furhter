import 'dart:convert';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/reader_fonts.dart';

class EpubReaderPreferences {
  const EpubReaderPreferences(
      {this.chapter = 0,
      this.offset = 0,
      this.fontSize = 20,
      this.dark = true,
      this.font = ReaderFonts.bookDefault});
  final int chapter, offset;
  final double fontSize;
  final bool dark;
  final ReaderFont font;

  static Future<EpubReaderPreferences> load(
      MyLibraryDb db, String fileName, int sectionCount) async {
    final saved = await db.getPreference('pagedEpub:$fileName', optional: true);
    int chapter = 0, offset = 0;
    if (saved is String) {
      try {
        final value = jsonDecode(saved) as Map<String, dynamic>;
        final savedChapter = value['chapter'] as int;
        final savedOffset = value['offset'] as int;
        chapter = savedChapter.clamp(0, sectionCount - 1).toInt();
        offset = savedOffset.clamp(0, 100000000).toInt();
      } catch (_) {/* An invalid position starts at the beginning. */}
    }
    final size = await db.getPreference('pagedReaderFontSize', optional: true);
    final dark = await db.getPreference('pagedReaderDark', optional: true);
    final font =
        await db.getPreference('pagedReaderFontFamily', optional: true);
    return EpubReaderPreferences(
        chapter: chapter,
        offset: offset,
        fontSize: (double.tryParse('$size') ?? 20).clamp(12, 32).toDouble(),
        dark: (dark ?? 1) == 1,
        font: ReaderFonts.resolve(font));
  }
}
