import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../enrichment/safe_lecture_html.dart';

class LectureHtmlView extends StatefulWidget {
  const LectureHtmlView({super.key, required this.content});

  final SafeLectureHtml content;

  @override
  State<LectureHtmlView> createState() => _LectureHtmlViewState();
}

class _LectureHtmlViewState extends State<LectureHtmlView> {
  MethodChannel? _channel;
  bool _failed = false;
  bool _loaded = false;

  Future<void> _created(int id) async {
    final channel = MethodChannel('studyhub/html/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'loaded' && mounted) {
        setState(() => _loaded = true);
      }
      if (call.method == 'failed' && mounted) {
        setState(() => _failed = true);
      }
    });
    try {
      await channel.invokeMethod<void>('load', widget.content.document);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The HTML preview could not open. Your notes are safe.'),
            const SizedBox(height: 16),
            SelectableText(widget.content.plainText),
          ],
        ),
      );
    }
    final surface = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => UiKitView(
        viewType: 'studyhub/html',
        onPlatformViewCreated: _created,
      ),
      TargetPlatform.macOS => AppKitView(
        viewType: 'studyhub/html',
        onPlatformViewCreated: _created,
      ),
      _ => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(widget.content.plainText),
      ),
    };
    final native =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return Stack(
      children: [
        Positioned.fill(child: surface),
        if (native && !_loaded)
          const Center(
            child: CircularProgressIndicator(
              key: ValueKey('html-preview-loading'),
            ),
          ),
      ],
    );
  }
}
