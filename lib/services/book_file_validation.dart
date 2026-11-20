import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

String normalizeBookFormat(String format) {
  final value = format.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  return switch (value) {
    'application/pdf' => 'pdf',
    'application/epub+zip' => 'epub',
    _ => value,
  };
}

/// Checks actual file contents, including older files already in the library.
/// ZIP contents stay on disk so large illustrated books are not read into RAM.
Future<void> validateBookFile(String filePath, String format) async {
  final file = File(filePath);
  if (!await file.exists() || await file.length() == 0) {
    throw const FormatException(
        'Book file is missing or empty. Please download it again.');
  }
  final handle = await file.open();
  late String header;
  try {
    header = latin1.decode(await handle.read(1024));
    if (normalizeBookFormat(format) == 'pdf') {
      if (!header.contains('%PDF-')) {
        throw const FormatException(
            'The server returned a page or invalid data instead of a PDF.');
      }
      final length = await handle.length();
      await handle.setPosition(length > 65536 ? length - 65536 : 0);
      final tail = latin1.decode(await handle.read(65536));
      if (!tail.contains('%%EOF')) {
        throw const FormatException('The PDF download is incomplete.');
      }
      return;
    }
  } finally {
    await handle.close();
  }

  switch (normalizeBookFormat(format)) {
    case 'epub':
    case 'cbz':
      if (!header.startsWith('PK\u0003\u0004')) {
        throw const FormatException(
            'The server returned a page or invalid data instead of a book.');
      }
      final input = InputFileStream(filePath);
      try {
        final archive = ZipDecoder().decodeStream(input);
        if (archive.files.isEmpty) {
          throw const FormatException('The book archive is empty or incomplete.');
        }
        if (normalizeBookFormat(format) == 'epub') {
          final mimetype = archive.findFile('mimetype');
          final container = archive.findFile('META-INF/container.xml');
          if (mimetype == null ||
              mimetype.size > 256 ||
              utf8.decode(mimetype.content).trim() != 'application/epub+zip' ||
              container == null ||
              container.size == 0) {
            throw const FormatException(
                'The downloaded ZIP is not an EPUB book.');
          }
        }
      } finally {
        input.closeSync();
      }
      return;
    case 'cbr':
      if (!header.startsWith('Rar!\u001a\u0007')) {
        throw const FormatException('The download is not a RAR comic book.');
      }
      return;
    default:
      final text = header.trimLeft().toLowerCase();
      if (text.startsWith('<!doctype html') || text.startsWith('<html')) {
        throw const FormatException(
            'The server returned a web page instead of a book.');
      }
  }
}
