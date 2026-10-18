import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:openlib/services/epub_pages.dart';
import 'package:openlib/services/epub_styles.dart';

void main() {
  test('linked typography, inline styles and paragraph headings are retained',
      () {
    final book = EpubBook()..Content = EpubContent();
    book.Content!.Html!['Text/chapter.xhtml'] = EpubTextContentFile()
      ..Content = '<html><head><link rel="stylesheet" href="../styles.css"></head>'
          '<body class="body"><p class="title">A Heading</p><p style="font-size:24px;font-style:italic;color:red">Text</p></body></html>';
    book.Content!.Css!['styles.css'] = EpubTextContentFile()
      ..Content =
          '.title{font-size:1.4em;font-weight:bold;margin:20px 0}body{line-height:1.3}';
    final result = epubSectionBody(book, 'Text/chapter.xhtml');
    expect(result, contains('font-weight:bold'));
    expect(result, contains('font-size:1.4em'));
    expect(result, contains('font-size:1.5em'));
    expect(result, contains('font-style:italic'));
    expect(result, isNot(contains('color:red')));
    expect(html.parseFragment(result).querySelector('.epub-content')!.classes,
        contains('body'));
  });
  test('publisher CSS cannot load resources or take over reader geometry', () {
    final result = safePublisherCss(
        '@import "https://example.com/evil.css";'
            'body{color:red;background:url(https://example.com);position:fixed;height:100vh;font-size:24px}'
            '@font-face{font-family:x;src:url(font.woff)} .title{font-weight:bold}',
        'scope');
    expect(result, contains('.scope .epub-content'));
    expect(result, contains('font-size:1.5em'));
    for (final forbidden in [
      'https:',
      'position:',
      'height:',
      '@font-face',
      'color:'
    ]) {
      expect(result, isNot(contains(forbidden)));
    }
  });
  test('font shorthand also preserves styled paragraph headings', () {
    final value = safeInlineTypography('font:italic bold 24px/1.2 serif');
    expect(value, contains('font-size:1.5em'));
    expect(value, contains('font-weight:bold'));
    expect(value, contains('font-style:italic'));
  });
  final userBook = Platform.environment['READER_TEST_EPUB'];
  test('uploaded book headings retain the publisher paragraph class', () async {
    final prepared =
        await compute(prepareEpub, await File(userBook!).readAsBytes());
    final index =
        prepared.$3.indexWhere((body) => body.contains('id="id_Toc70759518"'));
    expect(index, greaterThanOrEqualTo(0));
    final body = prepared.$3[index];
    expect(body, contains('font-weight:bold'));
    expect(body, contains('font-size:1.41667em'));
    expect(html.parseFragment(body).querySelector('#id_Toc70759518')!.classes,
        contains('block_13'));
    final output = Platform.environment['READER_TEST_HTML'];
    if (output != null) File(output).writeAsStringSync(body);
  }, skip: userBook == null);
}
