import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../domain/lecture_assignment.dart';
import '../domain/library.dart';

/// Packaging, not a script sanitizer. Arbitrary generated JS runs only in an
/// opaque-origin iframe. Both documents receive CSP before any executable code.
class AssignmentDocument {
  static String validate(String html) {
    if (html.trim().isEmpty ||
        utf8.encode(html).length > LectureAssignment.maxHtmlBytes) {
      throw const FormatException('The assignment is empty or too large.');
    }
    final doc = parser.parse(html);
    if (doc.body == null || doc.body!.text.trim().isEmpty) {
      throw const FormatException('The assignment has no readable content.');
    }
    return html;
  }

  static String _literal(String value) =>
      jsonEncode(value).replaceAll('<', r'\u003c').replaceAll('>', r'\u003e');
  static String policy(String nonce, {required bool host}) =>
      "default-src 'none'; script-src 'nonce-$nonce'; style-src 'unsafe-inline'; "
      "img-src data:; font-src 'none'; connect-src 'none'; media-src 'none'; "
      "frame-src ${host ? "'self' about:" : "'none'"}; object-src 'none'; "
      "base-uri 'none'; form-action 'none'; worker-src 'none'; manifest-src 'none'";

  static Future<String> build(LectureAssignment assignment) async {
    validate(assignment.html);
    final runtime = await rootBundle.loadString(
      'assets/assignments/runtime.js',
    );
    final host = await rootBundle.loadString('assets/assignments/host.js');
    return package(assignment, runtime: runtime, host: host);
  }

  static String package(
    LectureAssignment assignment, {
    required String runtime,
    required String host,
  }) {
    final nonce = newId();
    final doc = parser.parse(validate(assignment.html));
    for (final el in doc.querySelectorAll(
      'meta,base,link,iframe,frame,frameset,object,embed,applet,foreignObject',
    )) {
      el.remove();
    }
    for (final el in doc.querySelectorAll('*')) {
      for (final key in el.attributes.keys.toList()) {
        final name = key.toString().toLowerCase();
        final value = el.attributes[key]!;
        if (name.startsWith('on') ||
            name == 'srcdoc' ||
            name == 'nonce' ||
            name == 'action' ||
            name == 'formaction' ||
            name == 'target' ||
            name == 'download' ||
            name == 'ping' ||
            name == 'srcset' ||
            name == 'autofocus' ||
            (name == 'src' || name == 'href' || name.endsWith(':href')) &&
                !(el.localName == 'img' &&
                        RegExp(r'^data:image/(png|jpeg|webp);base64,')
                            .hasMatch(value) ||
                    value.startsWith('#'))) {
          el.attributes.remove(key);
        }
      }
      if (el.localName == 'script') {
        final type = el.attributes['type'];
        el.attributes.clear();
        if (type != null) {
          el.attributes['type'] = type;
        }
        el.attributes['nonce'] = nonce;
      }
    }
    final head = doc.head!;
    final meta = Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] = policy(nonce, host: false);
    final script = Element.tag('script')..attributes['nonce'] = nonce;
    script.text =
        'window.__studyhubInitialAnswers=JSON.parse(${_literal(assignment.answersJson)});\n$runtime';
    head.nodes.insertAll(0, [meta, script]);
    final child = doc.outerHtml;
    return '''<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="${policy(nonce, host: true)}"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}iframe{border:0;width:100%;height:100%}</style></head><body><iframe id="assignment" title="Interactive assignment" sandbox="allow-scripts"></iframe><script nonce="$nonce">window.__studyhubAnswers=${_literal(assignment.answersJson)};window.__studyhubDocument=${_literal(child)};\n$host</script></body></html>''';
  }

  /// Only bounded PNG answers are exported to the multimodal provider. Stored
  /// answer JSON remains the authoritative snapshot sent alongside these images.
  static List<Uint8List> inkImages(String answersJson) {
    LectureAssignment.validateAnswers(answersJson);
    final result = <Uint8List>[];
    var bytes = 0;
    for (final value in (jsonDecode(answersJson) as Map).values) {
      if (value is! Map || value['kind'] != 'ink' || value['png'] is! String) {
        continue;
      }
      final png = value['png'] as String;
      if (!png.startsWith('data:image/png;base64,')) {
        throw const FormatException('Invalid ink answer.');
      }
      final image = base64Decode(png.substring(22));
      bytes += image.length;
      if (result.length >= 12 ||
          bytes > LectureAssignment.maxAnswerBytes ||
          image.length < 24 ||
          ![
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ].asMap().entries.every((e) => image[e.key] == e.value)) {
        throw const FormatException('Invalid or oversized ink answer.');
      }
      result.add(image);
    }
    return result;
  }
}
