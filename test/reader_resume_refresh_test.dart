import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/reader_resume_refresh.dart';

void main() {
  testWidgets('unlock refreshes retained page without replacing its state',
      (tester) async {
    var resumes = 0;
    const pageKey = GlobalObjectKey('retained-reader');
    await tester.pumpWidget(MaterialApp(
      home: ReaderResumeRefresh(
        onResume: () async { resumes++; },
        child: const SizedBox(key: pageKey, child: Text('Current book page')),
      ),
    ));
    final element = pageKey.currentContext;
    final bounds = tester.getRect(find.byKey(pageKey));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(resumes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(resumes, 1);
    expect(pageKey.currentContext, same(element));
    expect(tester.getRect(find.byKey(pageKey)), bounds);
    expect(find.text('Current book page'), findsOneWidget);
  });

  testWidgets('relocking before the next frame cancels refresh', (tester) async {
    var resumes = 0;
    await tester.pumpWidget(MaterialApp(
      home: ReaderResumeRefresh(
        onResume: () async { resumes++; },
        child: const Text('Page'),
      ),
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(resumes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumes, 1);
  });

  testWidgets('closing reader during asynchronous refresh is safe', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: ReaderResumeRefresh(
        onResume: () => gate.future,
        child: const Text('Page'),
      ),
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
