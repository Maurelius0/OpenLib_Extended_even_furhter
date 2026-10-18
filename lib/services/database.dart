import 'dart:convert';
import 'package:crypto/crypto.dart';
// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// Project imports:
import 'package:openlib/services/files.dart';

class MyBook {
  final String id;
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String? publisher;
  final String? info;
  final String? description;
  final String? format;
  final String? fileName;

  MyBook(
      {required this.id,
      required this.title,
      required this.author,
      required this.thumbnail,
      required this.link,
      required this.publisher,
      required this.info,
      required this.format,
      required this.description,
      this.fileName});

  // Getter for compatibility with BookInfoWidget which expects 'md5'
  String get md5 => id;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'thumbnail': thumbnail,
      'link': link,
      'publisher': publisher,
      'info': info,
      'format': format,
      'description': description,
      'fileName': fileName
    };
  }

  @override
  String toString() {
    return 'MyBook{id: $id,title: $title,author: $author,thumbnail: $thumbnail,link: $link,publisher: $publisher,info: $info,format: $format,description:$description,fileName:$fileName}';
  }

  // Get actual filename - uses fileName if available, otherwise falls back to id.format
  String getFileName() {
    if (fileName != null && fileName!.isNotEmpty) {
      return fileName!;
    }
    return "$id.$format";
  }
}

class MyLibraryDb {
  static final MyLibraryDb instance = MyLibraryDb._internal();
  static Database? _database;
  MyLibraryDb._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String databasePath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      databasePath = directory.path;
      try {
        await Directory(databasePath).create(recursive: true);
      } catch (_) {}
    } else {
      databasePath = await getDatabasesPath();
    }
    final path = join(databasePath, 'mylibrary.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: (Database db, int version) async {
        await db.execute(
            'CREATE TABLE mybooks (id TEXT PRIMARY KEY, title TEXT,author TEXT,thumbnail TEXT,link TEXT,publisher TEXT,info TEXT,format TEXT,description TEXT,fileName TEXT)');
        await db.execute(
            'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        // Create these tables for all platforms (both mobile and desktop)
        await db.execute(
            'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT,completed INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        await db.execute(
            'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        List<dynamic> isTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['bookposition']);
        List<dynamic> isPreferenceTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['preferences']);
        List<dynamic> isbrowserOptionsExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['browserOptions']);
        if (isPreferenceTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Create bookposition table on all platforms if not exists
        if (isTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT)');
        }
        // Create browserOptions table on all platforms if not exists
        if (isbrowserOptionsExist.isEmpty) {
          await db.execute(
              'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Add fileName column if upgrading from version < 6
        if (oldVersion < 6) {
          try {
            await db.execute('ALTER TABLE mybooks ADD COLUMN fileName TEXT');
          } catch (_) {
            // Column might already exist
          }
        }
        // Tags and reading completion arrive with schema v7
        if (oldVersion < 7) {
          final hasTags = await db.query('sqlite_master',
              where: 'name = ?', whereArgs: ['booktags']);
          if (hasTags.isEmpty) {
            await db.execute(
                'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
          }
          try {
            await db.execute(
                'ALTER TABLE bookposition ADD COLUMN completed INTEGER DEFAULT 0');
          } catch (_) {
            // Column might already exist
          }
        }
      },
      onOpen: (db) async {
        final bookStorageDefaultDirectory =
            await getBookStorageDefaultDirectory;
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('darkMode', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('themeMode', 'system')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openPdfwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openEpubwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('bookStorageDirectory', '$bookStorageDefaultDirectory')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('showManualDownloadButton', 0)");
      },
    );
  }

  // Database dbInstance;
  String tableName = 'mybooks';

  int _metadataScore(MyBook book) {
    var score = 0;
    if ((book.thumbnail ?? '').trim().isNotEmpty) score += 100;
    if ((book.author ?? '').trim().isNotEmpty &&
        book.author?.toLowerCase() != 'unknown') {
      score += 20;
    }
    if (book.title != book.id &&
        book.title != book.getFileName().split('.').first) {
      score += 10;
    }
    if (book.link.isNotEmpty) score += 5;
    return score;
  }

  Future<void> _mergeFileEntries(Transaction txn, List<MyBook> books) async {
    if (books.isEmpty) return;
    books.sort((a, b) => _metadataScore(b).compareTo(_metadataScore(a)));
    final keep = books.first;
    await txn.insert(tableName, keep.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final other in books.skip(1)) {
      if (other.id == keep.id) continue;
      final tags = await txn
          .query('booktags', where: 'bookId = ?', whereArgs: [other.id]);
      for (final tag in tags) {
        await txn.insert('booktags', {'bookId': keep.id, 'tag': tag['tag']},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete('booktags', where: 'bookId = ?', whereArgs: [other.id]);
      await txn.delete(tableName, where: 'id = ?', whereArgs: [other.id]);
    }
  }

  Future<void> insert(MyBook book) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final all = listMapToMyBook(await txn.query(tableName));
      final peers =
          all.where((b) => b.getFileName() == book.getFileName()).toList();
      // Include the incoming record before choosing, so a late folder scan
      // cannot replace a downloaded book's title, author or cover.
      await _mergeFileEntries(txn, [book, ...peers]);
    });
  }

  Future<void> delete(String id) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ?',
      whereArgs: [id],
    );
    await dbInstance.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<MyBook?> getId(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return book.first;
    }
    return null;
  }

  Future<bool> checkIdExists(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<List<MyBook>> getAll() async {
    final dbInstance = await instance.database;
    final books = await dbInstance.transaction((txn) async {
      final books = listMapToMyBook(await txn.query(tableName));
      final groups = <String, List<MyBook>>{};
      for (final book in books) {
        groups.putIfAbsent(book.getFileName(), () => []).add(book);
      }
      for (final group in groups.values.where((g) => g.length > 1)) {
        await _mergeFileEntries(txn, group);
      }
      return listMapToMyBook(await txn.query(tableName));
    });
    return _hideIdenticalFiles(books);
  }

  /// Different filenames can represent identical downloads. Keep the files
  /// and rows, but show their richest metadata only once. Size/mtime cache
  /// prevents rehashing unchanged files on each library refresh.
  Future<List<MyBook>> _hideIdenticalFiles(List<MyBook> books) async {
    final directory =
        await getPreference('bookStorageDirectory', optional: true);
    if (directory == null) return books;
    final sizes = <int, List<(MyBook, File, FileStat)>>{};
    for (final book in books) {
      final file = File(join('$directory', book.getFileName()));
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      sizes.putIfAbsent(stat.size, () => []).add((book, file, stat));
    }
    final hidden = <String>{};
    for (final candidates in sizes.values.where((g) => g.length > 1)) {
      final hashes = <String, List<MyBook>>{};
      for (final candidate in candidates) {
        final (book, file, stat) = candidate;
        final key = 'libraryHash:${book.getFileName()}';
        final signature =
            '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
        final saved = await getPreference(key, optional: true);
        String hash;
        if (saved is String && saved.startsWith('$signature:')) {
          hash = saved.substring(signature.length + 1);
        } else {
          hash = (await sha256.bind(file.openRead()).first).toString();
          await savePreference(key, '$signature:$hash');
        }
        hashes.putIfAbsent(hash, () => []).add(book);
      }
      for (final identical in hashes.values.where((g) => g.length > 1)) {
        identical
            .sort((a, b) => _metadataScore(b).compareTo(_metadataScore(a)));
        final keep = identical.first;
        for (final other in identical.skip(1)) {
          hidden.add(other.id);
          for (final tag in await getTags(other.id)) {
            await addTag(keep.id, tag);
          }
          final oldPosition = await getBookState(other.getFileName());
          if (oldPosition != null &&
              (await getBookState(keep.getFileName()) ?? '').isEmpty) {
            await saveBookState(keep.getFileName(), oldPosition);
          }
          for (final prefix in ['pagedEpub:', 'readerActivity:']) {
            final saved = await getPreference('$prefix${other.getFileName()}',
                optional: true);
            if (saved != null &&
                await getPreference('$prefix${keep.getFileName()}',
                        optional: true) ==
                    null) {
              await savePreference('$prefix${keep.getFileName()}', saved);
            }
          }
        }
      }
    }
    return books.where((b) => !hidden.contains(b.id)).toList();
  }

  List<MyBook> listMapToMyBook(List<Map<String, dynamic>> maps) {
    List<MyBook> myBookList = List.generate(maps.length, (i) {
      return MyBook(
          id: maps[i]['id'],
          title: maps[i]['title'],
          author: maps[i]['author'],
          thumbnail: maps[i]['thumbnail'],
          link: maps[i]['link'],
          publisher: maps[i]['publisher'],
          info: maps[i]['info'],
          format: maps[i]['format'],
          description: maps[i]['description'],
          fileName: maps[i]['fileName']);
    });
    return myBookList.reversed.toList();
  }

  /// Keep reading activity separate from the resume position. Reflows and
  /// opening a book do not count as reading a second page.
  Future<bool> recordReaderPage(String fileName, String? page) async {
    final db = await instance.database;
    return db.transaction((txn) async {
      final key = 'readerActivity:$fileName';
      final rows =
          await txn.query('preferences', where: 'name = ?', whereArgs: [key]);
      var pages = <String>[];
      if (rows.isNotEmpty) {
        try {
          pages = (jsonDecode(rows.first['value'] as String) as List)
              .cast<String>();
        } catch (_) {}
      }
      final wasStarted = pages.length >= 2;
      if (!wasStarted && page != null && !pages.contains(page)) pages.add(page);
      await txn.insert('preferences', {'name': key, 'value': jsonEncode(pages)},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return !wasStarted && pages.length >= 2;
    });
  }

  Future<Map<String, bool>> getReaderActivityForAll() async {
    final db = await instance.database;
    final rows = await db.query('preferences',
        where: 'name LIKE ?', whereArgs: ['readerActivity:%']);
    final result = <String, bool>{};
    for (final row in rows) {
      try {
        result[(row['name'] as String).substring('readerActivity:'.length)] =
            (jsonDecode(row['value'] as String) as List).length >= 2;
      } catch (_) {}
    }
    return result;
  }

  Future<void> saveBookState(String fileName, String position) async {
    final dbInstance = await instance.database;
    await dbInstance.transaction((txn) async {
      final updated = await txn.update('bookposition', {'position': position},
          where: 'fileName = ?', whereArgs: [fileName]);
      if (updated == 0) {
        await txn.insert(
            'bookposition', {'fileName': fileName, 'position': position});
      }
    });
  }

  // ------------------------------------------------------------------
  // Tags: user-defined collections a book can belong to ('Favorites',
  // 'Sci-Fi', 'To Read', ...). One book, many tags; one tag, many books.
  // ------------------------------------------------------------------

  /// Assigns one tag to a book. Adding an existing pair is a no-op.
  Future<void> addTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'booktags',
      {'bookId': bookId, 'tag': tag.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes one tag from a book.
  Future<void> removeTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ? AND tag = ?',
      whereArgs: [bookId, tag],
    );
  }

  /// All tags of one book.
  Future<Set<String>> getTags(String bookId) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('booktags', where: 'bookId = ?', whereArgs: [bookId]);
    return rows.map((r) => r['tag'].toString()).toSet();
  }

  /// Every distinct tag in use, sorted alphabetically.
  Future<List<String>> getAllTags() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags',
        columns: ['tag'], groupBy: 'tag', orderBy: 'tag COLLATE NOCASE');
    return rows.map((r) => r['tag'].toString()).toList();
  }

  /// Map of bookId to its tag set, in one query - used to enrich the
  /// whole library without N+1 lookups.
  Future<Map<String, Set<String>>> getTagsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags');
    final map = <String, Set<String>>{};
    for (final row in rows) {
      map
          .putIfAbsent(row['bookId'].toString(), () => {})
          .add(row['tag'].toString());
    }
    return map;
  }

  // ------------------------------------------------------------------
  // Reading status: a book is completed when its position row is
  // flagged; in progress when a position exists but is not flagged.
  // ------------------------------------------------------------------

  /// Marks (or unmarks) a book as finished. The fileName key matches
  /// the bookposition table.
  Future<void> setCompleted(String fileName, bool completed) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'bookposition',
      {'fileName': fileName, 'position': '', 'completed': completed ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// True when the book is flagged completed.
  Future<bool> isCompleted(String fileName) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    if (rows.isEmpty) return false;
    return rows.first['completed'] == 1;
  }

  /// Map of fileName to saved position for the whole library - used
  /// to derive reading status without N+1 lookups.
  Future<Map<String, String?>> getPositionsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows)
        row['fileName'].toString(): row['position']?.toString()
    };
  }

  /// Map of fileName to completed flag for the whole library.
  Future<Map<String, bool>> getCompletedForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows) row['fileName'].toString(): row['completed'] == 1
    };
  }

  Future<void> deleteBookState(String fileName) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'bookposition',
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
  }

  Future<String?> getBookState(String fileName) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'fileName': data[i]['fileName'], 'position': data[i]['position']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['position'];
    } else {
      return null;
    }
  }

  Future<void> savePreference(String name, dynamic value) async {
    switch (value) {
      case bool _:
        value = value ? 1 : 0;
        break;
      case int _ || String _:
        break;
      default:
        throw 'Invalid type';
    }
    Database dbInstance = await instance.database;
    await dbInstance.insert(
      'preferences',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getPreference(String name, {bool optional = false}) async {
    Database dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('preferences', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      // Convert to int if possible
      int? preference = int.tryParse(dataList[0]['value']);
      if (preference != null) {
        return preference;
      }
      // Return string value if not int
      return dataList[0]['value'];
    }
    if (optional) {
      return null;
    }
    throw "Preference $name not found";
  }

  Future<void> setBrowserOptions(String name, String value) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'browserOptions',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getBrowserOptions(String name) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('browserOptions', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['value'];
    } else {
      return "";
    }
  }
}
