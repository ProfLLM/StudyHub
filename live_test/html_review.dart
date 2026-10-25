// Local-only review of previously returned public synthetic HTML. No provider,
// credentials, library, or network client is constructed by this entry point.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:studyhub/app/lecture_html_view.dart';
import 'package:studyhub/enrichment/safe_lecture_html.dart';

void main() {
  const payload = String.fromEnvironment('STUDYHUB_HTML_REVIEW');
  if (payload.isEmpty) throw StateError('Supply public saved HTML for review.');
  final cases = (jsonDecode(payload) as List).cast<Map<String, dynamic>>();
  runApp(MaterialApp(home: _Review(cases: cases)));
}

class _Review extends StatefulWidget {
  const _Review({required this.cases});
  final List<Map<String, dynamic>> cases;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved synthetic HTML · no model requests'),
    ),
    body: Column(
      children: [
        Wrap(
          children: [
            for (var i = 0; i < widget.cases.length; i++)
              TextButton(
                onPressed: () => setState(() => index = i),
                child: Text('${i + 1} ${widget.cases[i]['id']}'),
              ),
          ],
        ),
        Expanded(
          child: LectureHtmlView(
            key: ValueKey(index),
            content: SafeLectureHtml.parse(
              widget.cases[index]['html'] as String,
            ),
          ),
        ),
      ],
    ),
  );
}
