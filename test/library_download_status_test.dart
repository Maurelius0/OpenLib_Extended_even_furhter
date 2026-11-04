import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openlib/services/database.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

MyBook _book(String id) => MyBook(
      id: id,
      title: id,
      author: null,
      thumbnail: null,
      link: '',
      publisher: null,
      info: null,
      format: 'epub',
      description: null,
    );

void main() {
  test(
    'completed download refreshes categories without losing existing status',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp(
        'reader_categories_',
      );
      PathProviderPlatform.instance = _TestPaths(directory.path);
      final db = MyLibraryDb.instance;
      await db.savePreference('bookStorageDirectory', directory.path);
      for (final id in ['unread', 'reading', 'finished']) {
        await db.insert(_book(id));
      }
      await db.saveBookState('reading.epub', 'page-2');
      await db.saveBookState('finished.epub', 'last-page');
      await db.setCompleted('finished.epub', true);

      final container = ProviderContainer();
      final listener = container.listen(libraryBooksProvider, (_, __) {});
      addTearDown(() async {
        listener.close();
        container.dispose();
        await (await db.database).close();
        await directory.delete(recursive: true);
      });
      await container.read(libraryBooksProvider.future);
      expect((await container.read(myLibraryProvider.future)).length, 3);
      expect(container.read(libraryStatusFilterProvider), isNull);
      List<String> visible() =>
          container.read(organizedLibraryProvider).map((b) => b.id).toList();
      expect(visible(), ['finished', 'reading', 'unread']);
      container.read(libraryStatusFilterProvider.notifier).state =
          ReadingStatus.inProgress;
      expect(visible(), ['reading']);

      final bytes = List<int>.generate(1024, (i) => i % 251);
      final id = md5.convert(bytes).toString();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.add(bytes);
        await request.response.close();
      });
      final manager = container.read(downloadManagerProvider);
      await manager.initialize();
      final completed = manager.downloadsStream.firstWhere(
        (tasks) => tasks[id]?.status == DownloadStatus.completed,
      );
      final refreshed = Completer<void>();
      final refreshListener = container.listen(libraryBooksProvider, (_, next) {
        if (next.valueOrNull?.any((b) => b.id == id) == true &&
            !refreshed.isCompleted) {
          refreshed.complete();
        }
      });
      addTearDown(refreshListener.close);
      final url = 'http://127.0.0.1:${server.port}/book.epub';
      await manager.addDownload(
        DownloadTask(
          id: id,
          md5: id,
          title: 'New book',
          mirrors: [url],
          format: 'epub',
          link: url,
        ),
      );
      await completed.timeout(const Duration(seconds: 15));
      await refreshed.future.timeout(const Duration(seconds: 5));
      expect(visible(), ['reading']);
      container.read(libraryStatusFilterProvider.notifier).state = null;
      expect(visible(), [id, 'finished', 'reading', 'unread']);
      container.read(libraryStatusFilterProvider.notifier).state =
          ReadingStatus.completed;
      expect(visible(), ['finished']);
      expect((await container.read(myLibraryProvider.future)).length, 4);
    },
  );
}
