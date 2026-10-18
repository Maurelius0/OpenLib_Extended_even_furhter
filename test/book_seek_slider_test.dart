import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/book_seek_slider.dart';

void main() {
  testWidgets('drag previews locally and seeks only on release',
      (tester) async {
    var builds = 0;
    final seeks = <int>[];
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (_) {
      builds++;
      return BookSeekSlider(
          total: 300, page: 0, enabled: true, onSeek: seeks.add);
    }))));
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(150);
    await tester.pump();
    expect(builds, 1);
    expect(seeks, isEmpty);
    expect(find.text('Page 151 of 300'), findsNothing);
    expect(find.text('151/300'), findsOneWidget);
    expect(tester.getCenter(find.text('151/300')).dx,
        closeTo(tester.getCenter(find.byType(Slider)).dx, .1));
    expect(tester.getRect(find.text('151/300')).bottom,
        lessThan(tester.getRect(find.byType(Slider)).center.dy));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 150);
    final style = tester.widget<SliderTheme>(find.byType(SliderTheme));
    expect(style.data.trackHeight, 2);
    expect(style.data.thumbShape, isA<ReaderSliderThumb>());
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(150);
    expect(seeks, [150]);
  });
  testWidgets('previews coalesce, never overlap, and final destination wins',
      (tester) async {
    final pending = Completer<void>();
    final previews = <int>[];
    final commits = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookSeekSlider(
                total: 500,
                page: 0,
                enabled: true,
                onSeek: commits.add,
                onPreview: (page) async {
                  previews.add(page);
                  await pending.future;
                }))));
    Slider control() => tester.widget<Slider>(find.byType(Slider));
    control().onChangeStart!(0);
    control().onChanged!(10);
    control().onChanged!(50);
    control().onChanged!(100);
    await tester.pump(const Duration(milliseconds: 145));
    expect(previews, [100]);
    control().onChanged!(150);
    await tester.pump(const Duration(milliseconds: 160));
    expect(previews, [100]);
    control().onChangeEnd!(180);
    expect(commits, isEmpty);
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(commits, [180]);
    expect(previews, [100]);
  });
}
