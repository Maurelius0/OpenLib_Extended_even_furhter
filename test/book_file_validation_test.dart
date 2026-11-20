import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/book_file_validation.dart';
import 'support/book_fixture.dart';

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('book_'));
  tearDown(() => directory.delete(recursive: true));

  test('rejects a download-limit page even with a book filename', () async {
    final file = File('${directory.path}/guide.pdf');
    await file.writeAsString('<html>Download limit reached</html>');
    await expectLater(validateBookFile(file.path, 'pdf'),
        throwsA(isA<FormatException>()));
    await expectLater(validateBookFile(file.path, 'epub'),
        throwsA(isA<FormatException>()));
  });

  test('rejects empty and truncated files', () async {
    final file = File('${directory.path}/book');
    await file.writeAsBytes([]);
    await expectLater(validateBookFile(file.path, 'epub'),
        throwsA(isA<FormatException>()));
    await file.writeAsString('%PDF-1.7\ntruncated');
    await expectLater(validateBookFile(file.path, 'pdf'),
        throwsA(isA<FormatException>()));
    await file.writeAsBytes(epubFixture([1, 2, 3]).sublist(0, 20));
    await expectLater(validateBookFile(file.path, 'epub'), throwsException);
  });

  test('accepts EPUB and PDF contents with normalized metadata', () async {
    final file = File('${directory.path}/book');
    await file.writeAsBytes(epubFixture([1, 2, 3]));
    await validateBookFile(file.path, ' EPUB ');
    await file.writeAsBytes(await File('test/fixtures/sample.pdf').readAsBytes());
    await validateBookFile(file.path, 'application/pdf');
    expect(normalizeBookFormat('.PDF'), 'pdf');
    expect(normalizeBookFormat('application/epub+zip'), 'epub');
  });
}
