import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Editable PencilKit source and its portable, white-background PNG thumbnail.
/// Empty ink still has reloadable native source and a valid white PNG preview.
class InkDrawingUpdate {
  const InkDrawingUpdate({
    required this.drawing,
    required this.preview,
    required this.changeId,
  });

  final Uint8List drawing;
  final Uint8List preview;

  /// Transient per-view mutation count; persisted source starts at zero.
  final int changeId;

  factory InkDrawingUpdate.fromPlatform(Object? value) {
    if (value is! Map ||
        value['drawing'] is! Uint8List ||
        value['preview'] is! Uint8List ||
        value['changeId'] is! int ||
        (value['changeId'] as int) < 0) {
      throw const FormatException(
        'The ink canvas returned an invalid drawing.',
      );
    }
    return InkDrawingUpdate(
      drawing: value['drawing'] as Uint8List,
      preview: value['preview'] as Uint8List,
      changeId: value['changeId'] as int,
    );
  }
}

/// A single immutable ink revision and the PNG pages derived from that source.
class InkSnapshot extends InkDrawingUpdate {
  const InkSnapshot({
    required super.drawing,
    required super.preview,
    required super.changeId,
    required this.images,
  });

  final List<Uint8List> images;

  factory InkSnapshot.fromPlatform(Object? value) {
    final update = InkDrawingUpdate.fromPlatform(value);
    final images = (value as Map)['images'];
    if (images is! List || images.any((image) => image is! Uint8List)) {
      throw const FormatException('The ink snapshot returned invalid images.');
    }
    return InkSnapshot(
      drawing: update.drawing,
      preview: update.preview,
      changeId: update.changeId,
      images: List.unmodifiable(images.cast<Uint8List>()),
    );
  }
}

/// One controller per mounted lecture canvas. Call [flush] before navigation or
/// generation to include a stroke that has not reached its autosave debounce.
///
/// Errors are observable for inline UI and are rethrown to command callers.
class InkCanvasController {
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> initializationFailed = ValueNotifier(false);
  MethodChannel? _channel;
  ValueChanged<InkDrawingUpdate>? _onChanged;
  bool _disposed = false;

  void _attach(
    MethodChannel channel,
    ValueChanged<InkDrawingUpdate> onChanged,
  ) {
    if (_disposed) throw StateError('The ink controller has been disposed.');
    _channel = channel;
    _onChanged = onChanged;
    ready.value = false;
    initializationFailed.value = false;
    error.value = null;
  }

  void _detach(MethodChannel channel) {
    if (_channel != channel || _disposed) return;
    _channel = null;
    _onChanged = null;
    ready.value = false;
    initializationFailed.value = false;
  }

  void _report(Object exception) {
    if (_disposed) return;
    error.value = switch (exception) {
      PlatformException(:final message) => message ?? 'Ink canvas unavailable.',
      MissingPluginException() => 'The native ink canvas is unavailable.',
      _ => exception.toString(),
    };
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null || !ready.value) {
      throw StateError('Wait for the ink canvas to finish loading.');
    }
    try {
      final result = await channel.invokeMethod<T>(method, arguments);
      if (!_disposed) error.value = null;
      return result;
    } catch (exception) {
      _report(exception);
      rethrow;
    }
  }

  Future<InkDrawingUpdate?> flush() async {
    if (_channel == null) return null;
    // Native input is disabled when the initial source could not be opened.
    // Nothing from that view can be dirty; keep the original file untouched.
    // A view still loading, or one with a later command failure, must flush.
    if (initializationFailed.value && !ready.value) return null;
    final value = await _invoke<Object>('flush');
    try {
      final update = InkDrawingUpdate.fromPlatform(value);
      _onChanged?.call(update);
      return update;
    } catch (exception) {
      _report(exception);
      rethrow;
    }
  }

  /// Source bytes, preview, pages, and changeId come from one native PKDrawing
  /// value. The caller records the returned revision before starting generation.
  Future<InkSnapshot> captureSnapshot() async {
    final value = await _invoke<Object>('captureSnapshot');
    try {
      return InkSnapshot.fromPlatform(value);
    } catch (exception) {
      _report(exception);
      rethrow;
    }
  }

  /// Ordered PNG pages with overlap at page boundaries. Empty ink returns [].
  /// Excessive output fails explicitly; it is never silently truncated.
  Future<List<Uint8List>> exportImages() async {
    final value = await _invoke<Object>('exportImages');
    if (value is! List || value.any((image) => image is! Uint8List)) {
      const exception = FormatException('Ink images could not be exported.');
      _report(exception);
      throw exception;
    }
    return value.cast<Uint8List>();
  }

  Future<void> undo() async => _invoke<void>('undo');
  Future<void> redo() async => _invoke<void>('redo');
  Future<void> clear() async => _invoke<void>('clear');

  /// Off by default: Pencil draws and a finger pans. Enable explicitly for
  /// simulator/mouse or finger testing; disable again for one-finger panning.
  Future<void> setFingerDrawing(bool enabled) async =>
      _invoke<void>('setFingerDrawing', enabled);

  /// Hides the native tool picker while the canvas is kept offstage.
  Future<void> setActive(bool active) async =>
      _invoke<void>('setActive', active);

  /// Native implementation exists only in DEBUG builds. Exercises real
  /// PencilKit source/export with recorded synthetic input, not Pencil hardware.
  @visibleForTesting
  Future<void> seedSyntheticDrawingForTesting() async =>
      _invoke<void>('seedSyntheticDrawing');

  void dispose() {
    _disposed = true;
    _channel = null;
    _onChanged = null;
    ready.dispose();
    error.dispose();
    initializationFailed.dispose();
  }
}

class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.lectureId,
    this.initialDrawing,
    required this.onChanged,
    required this.controller,
  });

  final String lectureId;
  final Uint8List? initialDrawing;
  final ValueChanged<InkDrawingUpdate> onChanged;
  final InkCanvasController controller;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> with WidgetsBindingObserver {
  MethodChannel? _channel;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channel = _channel;
    if (oldWidget.lectureId != widget.lectureId && channel != null) {
      oldWidget.controller._detach(channel);
      channel.setMethodCallHandler(null);
      _channel = null;
    } else if (oldWidget.controller != widget.controller && channel != null) {
      oldWidget.controller._detach(channel);
      widget.controller._attach(channel, (update) => widget.onChanged(update));
      unawaited(_initialize(channel));
    }
    // Source is loaded only when the native view is created. Autosave rebuilds
    // must never assign an older PKDrawing over a stroke being written.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && widget.controller.ready.value) {
      unawaited(widget.controller.flush().catchError((Object _) => null));
    }
  }

  Future<void> _initialize(MethodChannel channel) async {
    try {
      await channel.invokeMethod<void>('initialize');
      if (mounted && channel == _channel) {
        widget.controller.initializationFailed.value = false;
        widget.controller.ready.value = true;
      }
    } catch (exception) {
      if (mounted && channel == _channel) {
        widget.controller.initializationFailed.value = true;
        widget.controller._report(exception);
      }
    }
  }

  void _created(int id) {
    final oldChannel = _channel;
    if (oldChannel != null) {
      widget.controller._detach(oldChannel);
      oldChannel.setMethodCallHandler(null);
    }
    final channel = MethodChannel('studyhub/ink/$id');
    _channel = channel;
    widget.controller._attach(channel, (update) => widget.onChanged(update));
    channel.setMethodCallHandler((call) async {
      if (!mounted || channel != _channel) return;
      try {
        switch (call.method) {
          case 'drawingChanged':
            if (widget.controller.ready.value) {
              widget.onChanged(InkDrawingUpdate.fromPlatform(call.arguments));
            }
          case 'inkError':
            widget.controller._report(
              PlatformException(
                code: 'ink',
                message: call.arguments as String?,
              ),
            );
        }
      } catch (exception) {
        widget.controller._report(exception);
      }
    });
    unawaited(_initialize(channel));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null) {
      channel.setMethodCallHandler(null);
      widget.controller._detach(channel);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(child: Text('Handwriting is available on iPad.'));
    }
    return Column(
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
                        Text(error, semanticsLabel: 'Ink error: $error'),
                        if (widget.controller.initializationFailed.value)
                          TextButton(
                            onPressed: () {
                              widget.controller.initializationFailed.value =
                                  false;
                              widget.controller.error.value = null;
                              setState(() => _attempt++);
                            },
                            child: const Text('Retry opening ink'),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        Expanded(
          child: UiKitView(
            key: ValueKey('ink-${widget.lectureId}-$_attempt'),
            viewType: 'studyhub/ink',
            creationParams: {
              'lectureId': widget.lectureId,
              if (widget.initialDrawing != null)
                'drawing': widget.initialDrawing,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _created,
          ),
        ),
      ],
    );
  }
}
