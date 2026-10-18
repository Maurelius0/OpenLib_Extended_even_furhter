import 'dart:convert';
import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/epub_pages.dart';

EpubChapter chapter(String name, String file,
        {String? anchor, List<EpubChapter> children = const []}) =>
    EpubChapter()
      ..Title = name
      ..ContentFileName = file
      ..Anchor = anchor
      ..SubChapters = children;

void main() {
  test(
      'several chapters and subsections in one file keep their contents anchors',
      () {
    final book = EpubBook()
      ..Title = 'Book'
      ..Content = EpubContent();
    book.Chapters = [
      chapter('Part One', 'chapter%201.xhtml', children: [
        chapter('Chapter 1', 'chapter%201.xhtml', anchor: 'one'),
        chapter('Chapter 2: Money', 'chapter%201.xhtml',
            anchor: 'two',
            children: [
              chapter('  The\n Fundamentals ', 'chapter%201.xhtml',
                  anchor: 'fundamentals'),
            ]),
      ]),
      chapter('Epilogue', 'end.xhtml')
    ];
    final labels = epubReadingLabels(book, ['chapter 1.xhtml', 'end.xhtml']);
    expect(labels[0].map((l) => l.title),
        ['Part One', 'Chapter 1', 'Chapter 2: Money', 'The Fundamentals']);
    expect(
        labels[0].map((l) => l.anchor), [null, 'one', 'two', 'fundamentals']);
    expect(labels[1].single.title, 'Epilogue');
  });
  test(
      'a body heading supplies the section name when the head repeats the book title',
      () {
    final book = EpubBook()
      ..Title = 'Book'
      ..Content = EpubContent();
    book.Content!.Html!['chapter.xhtml'] = EpubTextContentFile()
      ..Content =
          '<html><head><title>Book</title></head><body><h1>A real chapter title</h1></body></html>';
    expect(epubReadingLabels(book, ['chapter.xhtml']).single.single.title,
        'A real chapter title');
  });
  final userBook = Platform.environment['READER_TEST_EPUB'];
  test(
      'the supplied EPUB exposes both chapters and subsections in the same spine file',
      () async {
    final prepared =
        await compute(prepareEpub, await File(userBook!).readAsBytes());
    final index =
        prepared.$3.indexWhere((body) => body.contains('id="id_Toc70759518"'));
    final labels = prepared.$4[index];
    expect(labels.any((l) => l.title.startsWith('Chapter 1:')), isTrue);
    expect(labels.any((l) => l.title.startsWith('Chapter 2:')), isTrue);
    expect(labels.any((l) => l.title == 'What is money?'), isTrue);
    expect(labels.any((l) => l.title == 'The Fundamentals'), isTrue);
    final output = Platform.environment['READER_TEST_SECTIONS'];
    if (output != null) {
      File(output).writeAsStringSync(jsonEncode(
          labels.map((l) => {'title': l.title, 'anchor': l.anchor}).toList()));
    }
  }, skip: userBook == null);
}
