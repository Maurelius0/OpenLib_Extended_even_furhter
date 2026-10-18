import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/reader_screen_timeout.dart';
import 'package:openlib/ui/components/book_reader_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <bool>[];
  setUp(() {
    events.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ReaderScreenTimeout.channel, (call) async {
          expect(call.method, 'setReading');
          events.add(call.arguments as bool);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ReaderScreenTimeout.channel, null);
  });

  testWidgets('reader opens one session, overlays keep it, library closes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookReaderShell(
                    title: 'Book',
                    progress: '1 / 2',
                    previous: null,
                    next: null,
                    child: Builder(
                      builder: (readerContext) {
                        return TextButton(
                          onPressed: () => Navigator.of(readerContext).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const Scaffold(body: Text('Image viewer')),
                            ),
                          ),
                          child: const Text('Open image'),
                        );
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('Open book'),
            );
          },
        ),
      ),
    );
    expect(events, isEmpty);
    await tester.tap(find.text('Open book'));
    await tester.pumpAndSettle();
    expect(events, [true]);
    await tester.tap(find.text('Open image'));
    await tester.pumpAndSettle();
    expect(events, [true]);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(events, [true]);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(events, [true, false]);
    expect(find.text('Open book'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('other platforms do not call the Android channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await ReaderScreenTimeout.setReading(true);
    await ReaderScreenTimeout.setReading(false);
    expect(events, isEmpty);
  });
}
