import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';

const _properties = {
  'font',
  'font-size',
  'font-family',
  'font-weight',
  'font-style',
  'font-variant',
  'line-height',
  'text-align',
  'text-indent',
  'text-transform',
  'text-decoration',
  'text-decoration-line',
  'letter-spacing',
  'word-spacing',
  'white-space',
  'vertical-align',
  'margin',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'padding',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'list-style-type',
  'list-style-position',
  'break-inside',
  'break-after',
  'break-before',
  'page-break-inside',
  'page-break-after',
  'page-break-before',
  'orphans',
  'widows',
  'display',
};

String _print(TreeNode node) {
  final printer = CssPrinter();
  node.visit(printer);
  return printer.toString();
}

String _declarations(DeclarationGroup group) {
  final out = StringBuffer();
  for (final declaration in group.declarations.whereType<Declaration>()) {
    final property = declaration.property.toLowerCase();
    if (!_properties.contains(property) || declaration.expression == null) {
      continue;
    }
    var value = _print(declaration.expression!).trim();
    // Only typography values; no URLs, functions, custom variables or markup.
    if (value.isEmpty ||
        !RegExp(r'''^[a-zA-Z0-9\s.,%#'"/+\-]+$''').hasMatch(value)) {
      continue;
    }
    if (property == 'font') {
      final size = RegExp(
              r'(^|\s)([0-9]*\.?[0-9]+(?:px|pt|em|rem|%))(?:\s*/\s*([0-9]*\.?[0-9]+(?:px|pt|em|rem|%)?))?(?=\s|$)',
              caseSensitive: false)
          .firstMatch(value);
      if (size == null) continue;
      final expanded = StringBuffer('font-size:${size[2]};');
      if (size[3] != null) expanded.write('line-height:${size[3]};');
      final prefix = value.substring(0, size.start).split(RegExp(r'\s+'));
      for (final part in prefix) {
        if (part == 'italic' || part == 'oblique') {
          expanded.write('font-style:$part;');
        }
        if (part == 'bold' ||
            part == 'bolder' ||
            part == 'lighter' ||
            RegExp(r'^[1-9]00$').hasMatch(part)) {
          expanded.write('font-weight:$part;');
        }
        if (part == 'small-caps') expanded.write('font-variant:small-caps;');
      }
      final family = value.substring(size.end).trim();
      if (family.isNotEmpty) expanded.write('font-family:$family;');
      out.write(safeInlineTypography(expanded.toString()));
      continue;
    }
    if (property == 'font-size') {
      value = value.replaceAllMapped(
          RegExp(r'([0-9]*\.?[0-9]+)(px|pt|rem)\b', caseSensitive: false), (m) {
        final number = double.parse(m[1]!);
        final unit = m[2]!.toLowerCase();
        return '${unit == 'rem' ? number : number / (unit == 'pt' ? 12 : 16)}em';
      });
    }
    if (property == 'display' &&
        !{
          'block',
          'inline',
          'inline-block',
          'list-item',
          'table',
          'table-row',
          'table-cell'
        }.contains(value)) {
      continue;
    }
    out.write('$property:$value${declaration.important ? ' !important' : ''};');
  }
  return out.toString();
}

String safeInlineTypography(String source) {
  try {
    final rules = css.parse('x{$source}').topLevels.whereType<RuleSet>();
    return rules.isEmpty ? '' : _declarations(rules.first.declarationGroup);
  } catch (_) {
    return '';
  }
}

/// Preserve cascade/specificity, but confine rules to their EPUB section.
String safePublisherCss(String source, String scope,
    {String? Function(String)? importLocal, Set<String>? visited}) {
  final seen = visited ?? <String>{};
  String render(List<TreeNode> nodes) {
    final out = StringBuffer();
    for (final node in nodes) {
      if (node is RuleSet && node.selectorGroup != null) {
        final declarations = _declarations(node.declarationGroup);
        if (declarations.isEmpty) continue;
        final selectors = <String>[];
        for (final selector in node.selectorGroup!.selectors) {
          var text = _print(selector).trim();
          if (text.length > 512 ||
              RegExp(r'[<{}@\\]').hasMatch(text) ||
              text.contains(':has(')) {
            continue;
          }
          text = text
              .replaceAll(
                  RegExp(r'(?<![\w.#-])html(?![\w-])', caseSensitive: false),
                  '.epub-root')
              .replaceAll(
                  RegExp(r'(?<![\w.#-])body(?![\w-])', caseSensitive: false),
                  '.epub-content')
              .replaceAll(':root', '.epub-root');
          selectors.add('.$scope $text');
        }
        if (selectors.isNotEmpty) {
          out.write('${selectors.join(',')}{$declarations}');
        }
      } else if (node is MediaDirective) {
        final query = node.mediaQueries.map(_print).join(',');
        if (!RegExp(r'[<{}@;\\]').hasMatch(query)) {
          out.write('@media $query{${render(node.rules)}}');
        }
      } else if (node is ImportDirective &&
          importLocal != null &&
          seen.add(node.import)) {
        final local = importLocal(node.import);
        if (local != null) {
          out.write(safePublisherCss(local, scope,
              importLocal: importLocal, visited: seen));
        }
      }
    }
    return out.toString();
  }

  try {
    return render(css.parse(source).topLevels);
  } catch (_) {
    return '';
  }
}
