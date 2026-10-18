import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/mylibrary_page.dart';

LibraryBook book(int id, ReadingStatus status) => LibraryBook(
    book: MyBook(
        id: '$id',
        title: 'Book $id',
        author: null,
        thumbnail: null,
        link: '',
        publisher: null,
        info: null,
        format: 'epub',
        description: null),
    status: status);

void main() {
  for (final count in [0, 1, 3]) {
    testWidgets('status tabs remain usable with $count books', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final books =
          List.generate(count, (i) => book(i, ReadingStatus.values[i % 3]));
      final container = ProviderContainer(overrides: [
        libraryBooksProvider.overrideWith((ref) async => books),
        libraryTagsProvider.overrideWith((ref) async => <String>{}),
        activeDownloadsProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: const Scaffold(body: MyLibraryPage()))));
      await tester.pumpAndSettle();
      for (final entry in {
        'Unread': ReadingStatus.unread,
        'In Progress': ReadingStatus.inProgress,
        'Completed': ReadingStatus.completed,
      }.entries) {
        final chip = find.widgetWithText(FilterChip, entry.key);
        expect(chip, findsOneWidget);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(container.read(libraryStatusFilterProvider), entry.value);
        expect(container.read(organizedLibraryProvider).map((b) => b.book.id),
            books.where((b) => b.status == entry.value).map((b) => b.book.id));
        if (count > 0 && !books.any((b) => b.status == entry.value)) {
          expect(
              find.text('No books match the current filters'), findsOneWidget);
        }
        for (final label in ['Unread', 'In Progress', 'Completed']) {
          expect(find.widgetWithText(FilterChip, label), findsOneWidget);
        }
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(container.read(libraryStatusFilterProvider), isNull);
        expect(container.read(organizedLibraryProvider).length, count);
      }
    });
  }
}
