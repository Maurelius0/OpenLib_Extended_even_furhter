import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/epub_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = MyLibraryDb.instance;
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = Directory.systemTemp.createTempSync('epub_first_open_');
    PathProviderPlatform.instance = _TestPaths(directory.path);
    await db.database;
  });
  setUp(() async {
    await (await db.database)
        .delete('preferences', where: 'name LIKE ?', whereArgs: ['paged%']);
  });
  tearDownAll(() async {
    await (await db.database).close();
    directory.deleteSync(recursive: true);
  });
  test('first EPUB opens with defaults when all reader preferences are absent',
      () async {
    final prefs = await EpubReaderPreferences.load(db, 'first.epub', 3);
    expect(prefs.chapter, 0);
    expect(prefs.offset, 0);
    expect(prefs.fontSize, 20);
    expect(prefs.dark, isTrue);
    expect(prefs.font.id, 'default');
  });
  test('a new book starts at the beginning and keeps existing reading settings',
      () async {
    await db.savePreference('pagedReaderFontSize', '28');
    await db.savePreference('pagedReaderDark', 0);
    final prefs = await EpubReaderPreferences.load(db, 'new.epub', 3);
    expect(prefs.chapter, 0);
    expect(prefs.offset, 0);
    expect(prefs.fontSize, 28);
    expect(prefs.dark, isFalse);
  });
  test('existing saved position still resumes correctly', () async {
    await db.savePreference(
        'pagedEpub:saved.epub', '{"chapter":2,"offset":145}');
    final prefs = await EpubReaderPreferences.load(db, 'saved.epub', 3);
    expect(prefs.chapter, 2);
    expect(prefs.offset, 145);
  });
  test('malformed position and text size use safe defaults', () async {
    await db.savePreference('pagedEpub:bad.epub', 'broken JSON');
    await db.savePreference('pagedReaderFontSize', 'invalid');
    final prefs = await EpubReaderPreferences.load(db, 'bad.epub', 3);
    expect(prefs.chapter, 0);
    expect(prefs.offset, 0);
    expect(prefs.fontSize, 20);
  });
  test('font choice persists across books and invalid choices use book default',
      () async {
    await db.savePreference('pagedReaderFontFamily', 'opendyslexic');
    for (final file in ['first.epub', 'second.epub']) {
      expect((await EpubReaderPreferences.load(db, file, 3)).font.id,
          'opendyslexic');
    }
    await db.savePreference('pagedReaderFontFamily', 'not-a-bundled-font');
    expect((await EpubReaderPreferences.load(db, 'third.epub', 3)).font.id,
        'default');
  });
  test('required preferences retain their existing missing-value error',
      () async {
    await expectLater(db.getPreference('pagedMissing'),
        throwsA('Preference pagedMissing not found'));
    expect(await db.getPreference('pagedMissing', optional: true), isNull);
  });
  test('reading requires two different pages beyond the cover and persists',
      () async {
    expect(await db.recordReaderPage('reading.epub', null), isFalse);
    expect((await db.getReaderActivityForAll())['reading.epub'], isFalse);
    await db.savePreference(
        'pagedEpub:reading.epub', '{"chapter":0,"offset":0}');
    expect(await db.recordReaderPage('reading.epub', '0:1'), isFalse);
    expect(await db.recordReaderPage('reading.epub', '0:1'), isFalse);
    expect((await db.getReaderActivityForAll())['reading.epub'], isFalse);
    expect(await db.recordReaderPage('reading.epub', '0:2'), isTrue);
    expect((await db.getReaderActivityForAll())['reading.epub'], isTrue);
    expect(await db.recordReaderPage('reading.epub', null), isFalse);
    expect((await db.getReaderActivityForAll())['reading.epub'], isTrue);
  });
  test('saving PDF resume positions preserves completed status', () async {
    await db.setCompleted('finished.pdf', true);
    await db.saveBookState('finished.pdf', '3');
    expect(await db.isCompleted('finished.pdf'), isTrue);
    expect(await db.getBookState('finished.pdf'), '3');
  });
  MyBook entry(String id, {bool full = false, String file = 'same.epub'}) =>
      MyBook(
          id: id,
          title: full ? 'The Book' : id,
          author: full ? 'Author' : 'Unknown',
          thumbnail: full ? 'cover.jpg' : '',
          link: full ? 'book-link' : '',
          publisher: '',
          info: '',
          format: 'epub',
          description: '',
          fileName: file);

  test(
      'same-file duplicate is repaired while keeping metadata, tags and position',
      () async {
    final sql = await db.database;
    await sql.insert('mybooks', entry('placeholder').toMap());
    await sql.insert('mybooks', entry('downloaded', full: true).toMap());
    await db.addTag('placeholder', 'Favorites');
    await db.saveBookState('same.epub', 'resume');
    final books = await db.getAll();
    expect(books.where((b) => b.getFileName() == 'same.epub').single.id,
        'downloaded');
    expect(await db.getTags('downloaded'), contains('Favorites'));
    expect(await db.getBookState('same.epub'), 'resume');
    await db.insert(entry('late-scan'));
    expect(
        (await db.getAll())
            .where((b) => b.getFileName() == 'same.epub')
            .single
            .thumbnail,
        'cover.jpg');
  });
  test('identical titles in different files remain separate', () async {
    await db.insert(entry('edition-a', full: true, file: 'edition-a.epub'));
    await db.insert(entry('edition-b', full: true, file: 'edition-b.epub'));
    final books = await db.getAll();
    expect(
        books.where((b) => b.getFileName().startsWith('edition-')).length, 2);
  });
  test('identical EPUB files under different names show only rich metadata',
      () async {
    final folder = Directory('${directory.path}/books')..createSync();
    File('${folder.path}/rich.epub').writeAsStringSync('identical contents');
    File('${folder.path}/import.epub').writeAsStringSync('identical contents');
    File('${folder.path}/other.epub').writeAsStringSync('different contents');
    await db.savePreference('bookStorageDirectory', folder.path);
    await db.insert(entry('rich', full: true, file: 'rich.epub'));
    await db.insert(entry('import', file: 'import.epub'));
    await db.insert(entry('other', file: 'other.epub'));
    await db.addTag('import', 'Imported');
    final books = await db.getAll();
    expect(books.any((b) => b.id == 'rich'), isTrue);
    expect(books.any((b) => b.id == 'import'), isFalse);
    expect(books.any((b) => b.id == 'other'), isTrue);
    expect(File('${folder.path}/import.epub').existsSync(), isTrue);
    expect(await db.getTags('rich'), contains('Imported'));
    expect((await db.getAll()).any((b) => b.id == 'import'), isFalse);
  });
}
