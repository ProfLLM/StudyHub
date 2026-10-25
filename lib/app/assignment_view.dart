import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/lecture_assignment.dart';
import '../enrichment/assignment_document.dart';

class AssignmentController {
  MethodChannel? _channel;
  final ready = ValueNotifier(false);
  final error = ValueNotifier<String?>(null);
  ValueChanged<String>? _changed;
  bool _initialFailure = false;

  Future<void> flush() async {
    if (_channel == null || _initialFailure) return;
    if (!ready.value) throw StateError('Wait for the assignment to load.');
    try {
      final answers = await _channel!
          .invokeMethod<String>('flush')
          .timeout(const Duration(seconds: 8));
      if (answers == null) throw const FormatException('Missing answers.');
      LectureAssignment.validateAnswers(answers);
      _changed?.call(answers);
      error.value = null;
    } catch (_) {
      error.value = 'Could not capture answers. Retry before leaving or requesting review.';
      rethrow;
    }
  }

  void dispose() {
    ready.dispose();
    error.dispose();
  }
}

class AssignmentView extends StatefulWidget {
  const AssignmentView({
    super.key,
    required this.assignment,
    required this.controller,
    required this.onChanged,
  });
  final LectureAssignment assignment;
  final AssignmentController controller;
  final ValueChanged<String> onChanged;
  @override
  State<AssignmentView> createState() => _AssignmentViewState();
}

class _AssignmentViewState extends State<AssignmentView>
    with WidgetsBindingObserver {
  MethodChannel? _channel;
  Timer? _timeout;
  int _attempt = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _fail(String message) {
    if (!mounted) return;
    if (!widget.controller.ready.value) {
      widget.controller._initialFailure = true;
    }
    widget.controller.error.value = message;
  }

  Future<void> _created(int id) async {
    _timeout?.cancel();
    _channel?.setMethodCallHandler(null);
    final controller = widget.controller;
    final channel = MethodChannel('studyhub/assignment/$id');
    _channel = channel;
    controller._channel = channel;
    controller._changed = (s) => widget.onChanged(s);
    controller.ready.value = false;
    controller._initialFailure = false;
    channel.setMethodCallHandler((call) async {
      if (!mounted || channel != _channel) return;
      if (call.method == 'ready') {
        _timeout?.cancel();
        controller._initialFailure = false;
        controller.ready.value = true;
        controller.error.value = null;
      }
      if (call.method == 'failed') {
        _fail(
          'Assignment unavailable or answers could not be saved. Retry opening it; saved answers are preserved.',
        );
      }
      if (call.method == 'answers') {
        try {
          final json = call.arguments as String;
          LectureAssignment.validateAnswers(json);
          widget.onChanged(json);
        } catch (_) {
          _fail(
            'The assignment returned invalid answers. Your last saved answers are preserved.',
          );
        }
      }
    });
    try {
      final document = await AssignmentDocument.build(widget.assignment);
      if (!mounted || channel != _channel) return;
      await channel.invokeMethod<void>('load', document);
      if (!mounted || channel != _channel || controller.ready.value) return;
      _timeout = Timer(
        const Duration(seconds: 15),
        () => _fail('The assignment did not finish loading. Retry opening it.'),
      );
    } catch (error) {
      if (error is PlatformException && error.code == 'unsupported_os') {
        _fail(
          'Interactive assignments require iPadOS 16 or macOS 13 or later. Your saved assignments and answers are preserved.',
        );
        return;
      }
      assert(() {
        debugPrint(
          'Assignment renderer failure: ${error is PlatformException ? error.code : error.runtimeType}',
        );
        return true;
      }());
      _fail('The assignment could not open. Your saved answers are preserved.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && widget.controller.ready.value) {
      unawaited(widget.controller.flush().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    _channel?.setMethodCallHandler(null);
    if (widget.controller._channel == _channel) {
      widget.controller._channel = null;
      widget.controller._changed = null;
      widget.controller.ready.value = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return const Center(
        child: Text('Interactive assignments are available on iPad and macOS.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: widget.controller.error,
          builder: (context, error, _) => error == null
              ? const SizedBox.shrink()
              : Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(error),
                        TextButton(
                          onPressed: () {
                            widget.controller.error.value = null;
                            setState(() => _attempt++);
                          },
                          child: const Text('Retry opening assignment'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: defaultTargetPlatform == TargetPlatform.iOS
                    ? UiKitView(
                        key: ValueKey(_attempt),
                        viewType: 'studyhub/assignment',
                        onPlatformViewCreated: _created,
                      )
                    : AppKitView(
                        key: ValueKey(_attempt),
                        viewType: 'studyhub/assignment',
                        onPlatformViewCreated: _created,
                      ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: widget.controller.ready,
                builder: (context, ready, _) => ready
                    ? const SizedBox.shrink()
                    : const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
