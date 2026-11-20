import 'dart:typed_data';
import 'package:archive/archive.dart';

Uint8List epubFixture(List<int> padding) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>'))
    ..addFile(ArchiveFile.string('content.opf',
        '<package><metadata/><manifest/><spine/></package>'))
    ..addFile(ArchiveFile('padding.bin', padding.length, padding)
      ..compression = CompressionType.none);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
