import 'dart:convert';
import 'dart:typed_data';
import 'epub_styles.dart';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as paths;

List<String> readableEpubSpine(EpubBook book) {
  final result = <String>[];
  final manifest = book.Schema?.Package?.Manifest?.Items ?? [];
  for (final item in book.Schema?.Package?.Spine?.Items ?? []) {
    if (item.IsLinear == false) continue;
    final matches = manifest.where((m) => m.Id == item.IdRef);
    if (matches.isNotEmpty) {
      final href = matches.first.Href ?? '';
      if (book.Content?.Html?.containsKey(href) == true) result.add(href);
    }
  }
  return result;
}

/// Resolve only local book resources, never network or executable URLs.
String? epubLocalTarget(String section, String source) {
  try {
    final uri = Uri.parse(source);
    if (uri.hasScheme || uri.hasAuthority || source.startsWith('/')) {
      return null;
    }
    final file = uri.path.isEmpty
        ? section
        : paths.posix
            .join(paths.posix.dirname(section), Uri.decodeComponent(uri.path));
    final normalized = paths.posix.normalize(file);
    return '$normalized${uri.hasFragment ? '#${Uri.decodeComponent(uri.fragment)}' : ''}';
  } catch (_) {
    return null;
  }
}

String epubSectionBody(EpubBook book, String name) {
  final parsed = html.parse(book.Content!.Html![name]!.Content ?? '');
  final scope = 'epub-${name.hashCode.abs()}';
  String? localCss(String href, String base) {
    final target = epubLocalTarget(base, href)?.split('#').first;
    if (target == null) return null;
    for (final item in book.Content!.Css!.entries) {
      if (paths.posix.normalize(Uri.decodeFull(item.key)) == target) {
        return item.value.Content;
      }
    }
    return null;
  }

  final styles = StringBuffer();
  for (final element
      in parsed.querySelectorAll('style,link[rel="stylesheet"]')) {
    final href = element.attributes['href'];
    final source = element.localName == 'style'
        ? element.text
        : localCss(href ?? '', name);
    if (source != null) {
      final base = href == null ? name : epubLocalTarget(name, href) ?? name;
      styles.write(safePublisherCss(source, scope,
          importLocal: (value) => localCss(value, base)));
    }
  }
  for (final element in parsed.querySelectorAll(
    'script,style,link,iframe,object,embed,form,base,meta,foreignObject,animate,animateTransform,set',
  )) {
    element.remove();
  }
  String? imageData(String source) {
    final target = epubLocalTarget(name, source)?.split('#').first;
    if (target == null) return null;
    for (final entry
        in (book.Content?.Images ?? <String, EpubByteContentFile>{}).entries) {
      if (paths.posix.normalize(Uri.decodeFull(entry.key)) != target) continue;
      final image = entry.value;
      if (image.Content == null) return null;
      return 'data:${image.ContentMimeType ?? 'image/png'};base64,${base64Encode(image.Content!)}';
    }
    return null;
  }

  for (final element in parsed.querySelectorAll('*')) {
    final typography = safeInlineTypography(element.attributes['style'] ?? '');
    final source = element.attributes['src'] ??
        element.attributes['href'] ??
        element.attributes.entries
            .where((e) =>
                e.key.toString() == 'xlink:href' ||
                (e.key is dom.AttributeName &&
                    (e.key as dom.AttributeName).name == 'href'))
            .map((e) => e.value)
            .firstOrNull ??
        '';
    final target =
        element.localName == 'a' ? epubLocalTarget(name, source) : null;
    element.attributes.removeWhere((key, value) =>
        key.toString().toLowerCase().startsWith('on') ||
        key.toString().startsWith('data-reader') ||
        ['style', 'srcset', 'href', 'xlink:href', 'src']
            .contains(key.toString()) ||
        (key is dom.AttributeName && key.name == 'href'));
    if (typography.isNotEmpty) element.attributes['style'] = typography;
    if (element.localName == 'a' && target != null) {
      element.attributes['data-reader-target'] = target;
      element.attributes['role'] = 'link';
      element.attributes['tabindex'] = '0';
    }
    if (element.localName == 'img' || element.localName == 'image') {
      final data = imageData(source);
      if (data != null) {
        element.attributes[element.localName == 'img' ? 'src' : 'href'] = data;
      }
    }
  }
  final root = dom.Element.tag('div')..classes.add(scope);
  final htmlRoot = dom.Element.tag('div')..classes.add('epub-root');
  final body = dom.Element.tag('div')..classes.add('epub-content');
  for (final pair in [
    (parsed.documentElement, htmlRoot),
    (parsed.body, body)
  ]) {
    if (pair.$1 != null) pair.$2.attributes.addAll(pair.$1!.attributes);
  }
  htmlRoot.classes.add('epub-root');
  body.classes.add('epub-content');
  body.nodes.addAll(parsed.body?.nodes.toList() ?? []);
  htmlRoot.append(body);
  root.append(htmlRoot);
  return '<style>${styles.toString()}</style>${root.outerHtml}';
}

List<({String title, String target, int depth})> epubContents(
    EpubBook book, List<String> spine) {
  final entries = <({String title, String target, int depth})>[];
  void add(List<EpubChapter> chapters, int depth) {
    for (final chapter in chapters) {
      if (chapter.ContentFileName != null) {
        entries.add((
          title: chapter.Title ?? 'Section',
          target:
              '${chapter.ContentFileName}${chapter.Anchor == null ? '' : '#${Uri.decodeComponent(chapter.Anchor!)}'}',
          depth: depth
        ));
      }
      add(chapter.SubChapters ?? [], depth + 1);
    }
  }

  for (final item
      in book.Schema?.Package?.Manifest?.Items ?? <EpubManifestItem>[]) {
    if (!(item.Properties ?? '').split(RegExp(r'\s+')).contains('nav')) {
      continue;
    }
    final name = item.Href;
    final content = book.Content?.Html?[name]?.Content;
    if (name == null || content == null) continue;
    final parsed = html.parse(content);
    final nav = parsed
        .querySelectorAll('nav')
        .where((element) =>
            (element.attributes['epub:type'] ?? '')
                .split(' ')
                .contains('toc') ||
            element.attributes['role'] == 'doc-toc')
        .firstOrNull;
    if (nav == null) continue;
    for (final link in nav.querySelectorAll('a[href]')) {
      final target = epubLocalTarget(name, link.attributes['href']!);
      if (target == null) continue;
      var depth = -1;
      for (var parent = link.parent;
          parent != null && parent != nav;
          parent = parent.parent) {
        if (parent.localName == 'ol' || parent.localName == 'ul') depth++;
      }
      entries.add(
          (title: link.text.trim(), target: target, depth: depth.clamp(0, 8)));
    }
  }
  if (entries.isEmpty) add(book.Chapters ?? [], 0);
  if (entries.isEmpty) {
    for (final name in spine) {
      final parsed = html.parse(book.Content!.Html![name]!.Content ?? '');
      entries.add((
        title: parsed.querySelector('h1,h2,h3,title')?.text.trim() ??
            'Section ${entries.length + 1}',
        target: name,
        depth: 0
      ));
    }
  }
  return entries;
}

typedef EpubReadingLabel = ({String title, String? anchor});

/// Build once alongside chapter preparation, not on page turns. A single spine
/// file may contain several chapters and subsections addressed by TOC anchors.
List<List<EpubReadingLabel>> epubReadingLabels(
    EpubBook book, List<String> spine) {
  String decode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  final result = List.generate(spine.length, (_) => <EpubReadingLabel>[]);
  final indexes = {for (var i = 0; i < spine.length; i++) decode(spine[i]): i};
  for (final entry in epubContents(book, spine)) {
    final hash = entry.target.indexOf('#');
    final file = hash < 0 ? entry.target : entry.target.substring(0, hash);
    final index = indexes[decode(file)];
    final title = entry.title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (index == null || title.isEmpty || title == book.Title) continue;
    final anchor = hash < 0 ? null : decode(entry.target.substring(hash + 1));
    result[index].add((title: title, anchor: anchor));
  }
  for (var i = 0; i < spine.length; i++) {
    if (result[i].isNotEmpty) continue;
    final document = html.parse(book.Content?.Html?[spine[i]]?.Content ?? '');
    final title = (document.querySelector('body h1,body h2,body h3') ??
                document.querySelector('title'))
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
    if (title.isNotEmpty &&
        title != book.Title &&
        !RegExp(r'\.(?:xhtml|html)$', caseSensitive: false).hasMatch(title)) {
      result[i].add((title: title, anchor: null));
    }
  }
  return result;
}

/// Parse and prepare chapters once in a worker isolate, off the Flutter UI.
Future<(EpubBook, List<String>, List<String>, List<List<EpubReadingLabel>>)>
    prepareEpub(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  final spine = readableEpubSpine(book);
  return (
    book,
    spine,
    [for (final section in spine) epubSectionBody(book, section)],
    epubReadingLabels(book, spine),
  );
}
