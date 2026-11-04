import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:openlib/services/epub_pages.dart';

void main() {
  final path = Platform.environment['READER_TEST_EPUB'];
  test(
    'uploaded EPUB links keep valid destinations through sanitization',
    () async {
      final prepared = await compute(
        prepareEpub,
        await File(path!).readAsBytes(),
      );
      final documents = prepared.$3.map(html.parseFragment).toList();
      var local = 0, web = 0;
      for (final doc in documents) {
        for (final link in doc.querySelectorAll('[data-reader-target]')) {
          final target = link.attributes['data-reader-target']!;
          if (epubExternalLink(target) != null) {
            web++;
            continue;
          }
          final hash = target.indexOf('#');
          final file = hash < 0 ? target : target.substring(0, hash);
          final index = prepared.$2.indexWhere(
            (name) => canonicalEpubPath(name) == file,
          );
          expect(index, greaterThanOrEqualTo(0), reason: target);
          if (hash >= 0) {
            final anchor = target.substring(hash + 1);
            expect(
              documents[index]
                  .querySelectorAll('[id],[name]')
                  .any(
                    (element) =>
                        element.id == anchor ||
                        element.attributes['name'] == anchor,
                  ),
              isTrue,
              reason: target,
            );
          }
          local++;
        }
      }
      expect(local, greaterThan(100));
      expect(web, greaterThan(300));
      // Export one real chapter for browser gesture and anchor integration checks.
      final output = Platform.environment['READER_LINK_FIXTURE'];
      if (output != null) {
        await File(output).writeAsString(
          jsonEncode({'spine': prepared.$2, 'bodies': prepared.$3}),
        );
      }
    },
    skip: path == null,
  );
}
