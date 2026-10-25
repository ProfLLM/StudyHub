import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

/// Static content only. Native renderers additionally disable JavaScript and
/// all network/file loads; sanitizing markup is not the isolation boundary.
class SafeLectureHtml {
  SafeLectureHtml._(this.document, this.plainText);

  final String document;
  final String plainText;

  static const maxBytes = 4 * 1024 * 1024;
  static const contentSecurityPolicy =
      "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
      "img-src data:; font-src 'none'; connect-src 'none'; frame-src 'none'; "
      "object-src 'none'; base-uri 'none'; form-action 'none'; media-src 'none'";

  static const _tags = {
    'article', 'section', 'main', 'header', 'footer', 'aside', 'nav', 'div',
    'span', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'br', 'hr', 'strong',
    'b',
    'i',
    'em',
    'u',
    's',
    'del',
    'ins',
    'small',
    'sub',
    'sup',
    'mark',
    'blockquote',
    'pre', 'code', 'kbd', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table',
    'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption', 'colgroup', 'col',
    'figure', 'figcaption', 'details', 'summary', 'a', 'img', 'style',
    // Native WebKit supports static SVG and MathML without third-party scripts.
    'svg', 'g', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline',
    'polygon', 'text', 'tspan', 'defs', 'marker', 'clippath', 'lineargradient',
    'radialgradient', 'stop', 'pattern', 'title', 'desc', 'use', 'symbol',
    'math', 'mrow', 'mi', 'mn', 'mo', 'ms', 'mtext', 'mspace', 'msup',
    'msub', 'msubsup', 'mfrac', 'msqrt', 'mroot', 'mfenced', 'mtable',
    'mtr', 'mtd', 'munder', 'mover', 'munderover', 'menclose', 'mstyle',
    'mpadded', 'mphantom', 'semantics', 'annotation',
  };

  static const _dropTrees = {
    'script',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'applet',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'option',
    'link',
    'base',
    'meta',
    'noscript',
    'template',
    'foreignobject',
    'audio',
    'video',
    'source',
    'track',
    'animate',
    'animatetransform',
    'animatemotion',
    'set',
  };

  static const _attributes = {
    'id',
    'class',
    'style',
    'title',
    'role',
    'lang',
    'dir',
    'aria-label',
    'aria-labelledby',
    'aria-describedby',
    'aria-hidden',
    'alt',
    'width',
    'height',
    'colspan',
    'rowspan',
    'scope',
    'start',
    'type',
    'open',
    'viewbox',
    'preserveaspectratio',
    'xmlns',
    'x',
    'y',
    'x1',
    'x2',
    'y1',
    'y2',
    'cx',
    'cy',
    'r',
    'rx',
    'ry',
    'd',
    'points',
    'fill',
    'fill-opacity',
    'fill-rule',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-dasharray',
    'stroke-opacity',
    'opacity',
    'transform',
    'text-anchor',
    'dominant-baseline',
    'baseline-shift',
    'font-size',
    'font-family',
    'font-weight',
    'font-style',
    'dx',
    'dy',
    'marker-start',
    'marker-mid',
    'marker-end',
    'markerwidth',
    'markerheight',
    'refx',
    'refy',
    'orient',
    'markerunits',
    'clippathunits',
    'clip-path',
    'gradientunits',
    'gradienttransform',
    'patternunits',
    'patterncontentunits',
    'patterntransform',
    'offset',
    'stop-color',
    'stop-opacity',
    'display',
    'displaystyle',
    'mathvariant',
    'mathsize',
    'mathcolor',
    'mathbackground',
    'stretchy',
    'fence',
    'separator',
    'accent',
    'accentunder',
    'columnalign',
    'rowalign',
    'columnspacing',
    'rowspacing',
    'linethickness',
    'notation',
    'encoding',
    'scriptlevel',
  };

  factory SafeLectureHtml.parse(String source) {
    if (source.trim().isEmpty || utf8.encode(source).length > maxBytes) {
      throw const FormatException('HTML notes are empty or too large.');
    }
    var cleanedSource = source.trim();
    // A provider may wrap its otherwise complete result in a Markdown fence.
    if (cleanedSource.startsWith('```html') && cleanedSource.endsWith('```')) {
      cleanedSource = cleanedSource.substring(7, cleanedSource.length - 3);
    }
    final parsed = parser.parse(cleanedSource);
    final styles = <String>[];
    final pending = <({Element element, int depth})>[
      for (final element in parsed.children.reversed)
        (element: element, depth: 1),
    ];
    var elementCount = 0;
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final element = current.element;
      if (++elementCount > 20000) {
        throw const FormatException('HTML notes contain too many elements.');
      }
      if (current.depth > 128) {
        throw const FormatException('HTML notes are nested too deeply.');
      }
      final tag = element.localName?.toLowerCase() ?? '';
      if (_dropTrees.contains(tag)) {
        element.remove();
        continue;
      }
      // Never inspect children of a removed tree: a nested style must not
      // escape a discarded form, template, or SVG foreignObject.
      pending.addAll([
        for (final child in element.children.reversed)
          (element: child, depth: current.depth + 1),
      ]);
      if (tag == 'html' || tag == 'head' || tag == 'body') continue;
      if (!_tags.contains(tag)) {
        element.replaceWith(
          DocumentFragment()..nodes.addAll(element.nodes.toList()),
        );
        continue;
      }
      if (tag == 'style') {
        final css = _safeCss(element.text);
        if (css != null) styles.add(css);
        element.remove();
        continue;
      }
      for (final attribute in element.attributes.keys.toList()) {
        final name = attribute.toString().toLowerCase();
        final value = element.attributes[attribute]!;
        if (name == 'href' || name == 'xlink:href') {
          if ((tag == 'a' || tag == 'use') &&
              RegExp(r'^#[a-zA-Z][\w:.-]*$').hasMatch(value)) {
            continue;
          }
        } else if (name == 'src' && tag == 'img') {
          if (RegExp(r'^data:image/(png|jpeg|webp);base64,[a-zA-Z0-9+/=\s]+$')
              .hasMatch(value)) {
            continue;
          }
        } else if (_attributes.contains(name)) {
          if (name == 'style') {
            final css = _safeCss(value);
            if (css != null) {
              element.attributes[attribute] = css;
              continue;
            }
          } else if (_safeAttributeValue(value)) {
            // WebKit does not paint SVG context-stroke/context-fill markers
            // reliably. Inherit the diagram's text color as a visible fallback.
            if ((name == 'stroke' || name == 'fill') &&
                (value == 'context-stroke' || value == 'context-fill')) {
              element.attributes[attribute] = 'currentColor';
            }
            continue;
          }
        }
        element.attributes.remove(attribute);
      }
    }
    final body = parsed.body!;
    final text = body.text.trim();
    if (text.isEmpty && body.querySelector('svg, img, math') == null) {
      throw const FormatException('HTML notes have no readable content.');
    }
    final document =
        '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="$contentSecurityPolicy">
<style>
:root { color-scheme: light dark; }
body { font-family: -apple-system, sans-serif; padding: 24px; margin: 0 auto;
  max-width: 880px; line-height: 1.65; overflow-wrap: anywhere; }
img, svg { max-width: 100%; height: auto; } table { border-collapse: collapse; }
th, td { padding: 8px; text-align: left; } math { font-size: 1.15em; }
pre { white-space: pre-wrap; } @media (max-width: 500px) { body { padding: 16px; } }
</style>
${styles.map((css) => '<style>$css</style>').join('\n')}
</head><body>${body.innerHtml}</body></html>''';
    if (utf8.encode(document).length > maxBytes) {
      throw const FormatException('HTML notes are too large.');
    }
    return SafeLectureHtml._(document, text);
  }

  static String _withoutCssComments(String css) =>
      css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  static bool _safeAttributeValue(String value) {
    if (value.contains('\\')) return false;
    final normalized = _withoutCssComments(value);
    if (normalized.contains('/*')) return false;
    if (RegExp(r'url\s*\(', caseSensitive: false).hasMatch(normalized)) {
      return RegExp(r'^url\(#[a-zA-Z][\w:.-]*\)$').hasMatch(normalized);
    }
    return true;
  }

  static String? _safeCss(String css) {
    // Fail closed for escaped/URL-bearing CSS. CSP and WebKit request blocking
    // remain authoritative even for malformed or obfuscated CSS.
    final normalized = _withoutCssComments(css);
    if (normalized.contains('\\') ||
        normalized.contains('/*') ||
        RegExp(
          r'url\s*\(|(?:-[\w]+-)?image-set\s*\(|\bimage\s*\(|\bsrc\s*\(|'
          r'@import|@namespace|@font-face|@(?:-[\w]+-)?keyframes|expression\s*\(|</style',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      return null;
    }
    return normalized.replaceAll(
      RegExp(
        r'(?:-[\w]+-)?\b(?:animation|transition)[\w-]*\s*:[^;}]*;?',
        caseSensitive: false,
      ),
      '',
    );
  }
}
