import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:epubx/src/utils/zip_path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EPUB ZIP paths normalize relative parent segments', () {
    expect(ZipPathUtils.combine('OEBPS', '../jacket.xhtml'), 'jacket.xhtml');
    expect(ZipPathUtils.combine('OPS/Text', '../Images/map.png'),
        'OPS/Images/map.png');
    expect(ZipPathUtils.combine('OEBPS', 'chapter.xhtml'),
        'OEBPS/chapter.xhtml');
    expect(ZipPathUtils.combine('', 'OEBPS/../jacket.xhtml'), 'jacket.xhtml');
    expect(ZipPathUtils.combine('OEBPS', null), isNull);
  });

  test('EPUB reader loads a manifest item located above the OPF folder',
      () async {
    final archive = Archive();
    archive.addFile(ArchiveFile(
        'mimetype', 20, 'application/epub+zip'.codeUnits)
      ..compression = CompressionType.none);
    archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''));
    archive.addFile(ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:2bc09321-3272-4cd4-bd89-f4fab40a2f6e</dc:identifier>
    <dc:title>Path regression test</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
    <item id="jacket" href="../jacket.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="jacket"/>
    <itemref idref="chapter"/>
  </spine>
</package>'''));
    archive.addFile(ArchiveFile.string('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body><nav epub:type="toc"><ol>
    <li><a href="chapter.xhtml">Chapter One</a></li>
  </ol></nav></body>
</html>'''));
    archive.addFile(ArchiveFile.string('jacket.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Jacket</title></head><body><p>Jacket at ZIP root</p></body>
</html>'''));
    archive.addFile(ArchiveFile.string('OEBPS/chapter.xhtml', '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter One</title></head><body><p>Main text</p></body>
</html>'''));

    final bytes = ZipEncoder().encode(archive);
    expect(bytes, isNotNull);
    final book = await EpubReader.readBook(bytes!);
    expect(book.Content?.Html?['../jacket.xhtml']?.Content,
        contains('Jacket at ZIP root'));
    expect(book.Content?.Html?['chapter.xhtml']?.Content,
        contains('Main text'));
  });
}
