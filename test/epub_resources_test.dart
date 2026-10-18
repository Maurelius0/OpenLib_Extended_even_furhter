import 'dart:convert';
import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:openlib/services/epub_pages.dart';

void main() {
  test('contents links retain local destinations and fragment anchors', () {
    final book = EpubBook()..Content = EpubContent();
    book.Content!.Html!['Text/toc.xhtml'] = EpubTextContentFile()
      ..Content = '<a href="chapter%201.xhtml#part%202">Chapter</a>'
          '<a href="#local">Local</a><a href="https://example.com">External</a>'
          '<h2 id="local">Heading</h2>';
    final body = html.parseFragment(epubSectionBody(book, 'Text/toc.xhtml'));
    final links = body.querySelectorAll('a');
    expect(links[0].attributes['data-reader-target'],
        'Text/chapter 1.xhtml#part 2');
    expect(links[1].attributes['data-reader-target'], 'Text/toc.xhtml#local');
    expect(links[2].attributes['data-reader-target'], isNull);
    expect(body.querySelector('h2')!.id, 'local');
  });
  test('SVG cover and raster graphics embed actual local image bytes', () {
    final book = EpubBook()..Content = EpubContent();
    book.Content!.Images!['Images/cover art.png'] = EpubByteContentFile()
      ..Content = [1, 2, 3]
      ..ContentMimeType = 'image/png';
    book.Content!.Html!['Text/cover.xhtml'] = EpubTextContentFile()
      ..Content = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 800">'
          '<image width="600" height="800" xlink:href="../Images/cover%20art.png" /></svg>'
          '<img src="../Images/cover%20art.png" />';
    final body = html.parseFragment(epubSectionBody(book, 'Text/cover.xhtml'));
    final data = 'data:image/png;base64,${base64Encode([1, 2, 3])}';
    expect(body.querySelector('image')!.attributes['href'], data);
    expect(body.querySelector('img')!.attributes['src'], data);
    expect(body.querySelector('svg')!.attributes['viewBox'], '0 0 600 800');
  });
  test('unsafe destinations are rejected', () {
    for (final value in [
      'javascript:alert(1)',
      '//example.com/a',
      'https://example.com',
      '/etc/passwd'
    ]) {
      expect(epubLocalTarget('Text/a.xhtml', value), isNull);
    }
  });
}
