import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/epub_pages.dart';

void main() {
  test('reads a real EPUB in spine order and retains readable content',
      () async {
    final dir = Directory.systemTemp.createTempSync('paged_epub');
    try {
      final file = File('${dir.path}/sample.epub');
      _writeMinimalEpub(file);
      final prepared = await compute(prepareEpub, file.readAsBytesSync());
      final book = prepared.$1;
      expect(prepared.$3.single, contains('Hello reader.'));
      expect(readableEpubSpine(book), ['chapter1.xhtml']);
      expect(epubContents(book, readableEpubSpine(book)).single.target,
          'chapter1.xhtml#start');
      expect(
          epubSectionBody(book, 'chapter1.xhtml'), contains('Hello reader.'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
  test('book HTML cannot execute scripts or load remote resources', () {
    final book = EpubBook()..Content = EpubContent();
    book.Content!.Html!['chapter.xhtml'] = EpubTextContentFile()
      ..Content = '<html><body><script>bad()</script><p onclick="bad()">Hello</p>'
          '<iframe src="https://example.com"></iframe><img src="https://example.com/pixel.png">'
          '<a href="javascript:bad()">Footnote</a></body></html>';
    final body = epubSectionBody(book, 'chapter.xhtml');
    expect(body, contains('Hello'));
    expect(body, isNot(contains('script')));
    expect(body, isNot(contains('onclick')));
    expect(body, isNot(contains('https://')));
    expect(body, isNot(contains('javascript:')));
  });
}

/// Writes a structurally valid minimal EPUB 3 book.
void _writeMinimalEpub(File file) {
  final archive = Archive();
  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits)
    ..compression = CompressionType.none);
  archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''));
  archive.addFile(ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:0d3f1a5a-9d0a-4d0e-a4e9-6b6e6f6f6e6e</dc:identifier>
    <dc:title>Sample Book</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="toc" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
  </spine>
</package>'''));
  archive.addFile(ArchiveFile.string('OEBPS/chapter1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Chapter 1</title></head>
  <body><h1 id="start">Sample Chapter</h1><p>Hello reader.</p></body>
</html>'''));

  archive.addFile(ArchiveFile.string('OEBPS/nav.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml#start">Chapter 1</a></li></ol></nav></body></html>'''));
  final data = ZipEncoder().encode(archive);
  file.writeAsBytesSync(data);
}
