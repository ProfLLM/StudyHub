import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/chatgpt_subscription_provider.dart'
    show ChatGptSubscriptionProvider;
import '../ai/lecture_enrichment_provider.dart';
import '../domain/lecture_content.dart';
import '../domain/library.dart';
import '../enrichment/safe_lecture_html.dart';
import '../ink/ink_canvas.dart';
import '../persistence/lecture_content_store.dart';
import 'lecture_html_view.dart';

enum LectureView { ink, html }

class LectureWorkspace extends StatefulWidget {
  const LectureWorkspace({
    super.key,
    required this.lecture,
    required this.store,
    this.providers = const [],
    this.inkController,
  });

  final Lecture lecture;
  final LectureContentStore store;
  final List<LectureEnrichmentProvider> providers;
  final InkCanvasController? inkController;

  @override
  State<LectureWorkspace> createState() => LectureWorkspaceState();
}

class LectureWorkspaceState extends State<LectureWorkspace> {
  late final _ink = widget.inkController ?? InkCanvasController();
  LectureContent? _content;
  SafeLectureHtml? _html;
  bool _loadFailed = false;
  bool _saveFailed = false;
  bool _saving = false;
  bool _generating = false;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _preparingToLeave = false;
  bool _connected = false;
  bool _fingerDrawing = false;
  String? _message;
  LectureView _view = LectureView.ink;
  int _inkBaseRevision = 0;
  int _latestNativeChange = 0;
  int _saveSequence = 0;
  int _operation = 0;
  int _providerIndex = 0;
  Future<void> _saveTail = Future.value();
  LectureEnrichmentProvider? _activeProvider;

  bool get _accountBusy => _connecting || _disconnecting;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final content = await widget.store.load(widget.lecture.id);
      final connected = await _connectionStatus();
      SafeLectureHtml? html;
      if (content.html != null) {
        try {
          html = SafeLectureHtml.parse(content.html!);
        } on FormatException {
          // An invalid rendition never prevents access to editable ink.
        }
      }
      if (!mounted) return;
      setState(() {
        _content = content;
        _inkBaseRevision = content.inkRevision;
        _html = html;
        _connected = connected;
        if (content.hasHtml && html == null) {
          _message = 'The saved HTML could not be opened safely. Your ink is available; create HTML again to replace it.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<bool> _connectionStatus() async {
    if (widget.providers.isEmpty) return false;
    try {
      return await widget.providers[_providerIndex].isConnected;
    } catch (_) {
      return false;
    }
  }

  void _changed(InkDrawingUpdate update) {
    final current = _content;
    if (!mounted || current == null || update.changeId < _latestNativeChange) {
      return;
    }
    _latestNativeChange = update.changeId;
    final revision = _inkBaseRevision + update.changeId;
    if (revision <= current.inkRevision) return;
    try {
      final next = LectureContent(
        lectureId: current.lectureId,
        inkRevision: revision,
        drawing: update.drawing,
        preview: update.preview,
        html: current.html,
        htmlSourceRevision: current.htmlSourceRevision,
        htmlProvider: current.htmlProvider,
      );
      setState(() => _content = next);
      _enqueueSave(next);
    } on ArgumentError {
      setState(() {
        _saveFailed = true;
        _message =
            'These notes exceed the storage limit. Your saved notes are safe.';
      });
    }
  }

  void _enqueueSave(LectureContent content) {
    final sequence = ++_saveSequence;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    _saveTail = _saveTail.then((_) async {
      try {
        await widget.store.save(content);
        if (mounted && sequence == _saveSequence) {
          setState(() {
            _saving = false;
            _saveFailed = false;
          });
        }
      } catch (_) {
        if (mounted && sequence == _saveSequence) {
          setState(() {
            _saving = false;
            _saveFailed = true;
          });
        }
      }
    });
  }

  /// Parent navigation waits for the native debounce and the last file write.
  Future<bool> prepareToLeave() async {
    if (_generating || _connecting) _cancel();
    if (mounted) setState(() => _preparingToLeave = true);
    var mayLeave = false;
    try {
      if (_ink.ready.value) await _ink.setActive(false);
      await _ink.flush();
      while (true) {
        final sequence = _saveSequence;
        await _saveTail;
        if (sequence == _saveSequence) break;
      }
      mayLeave = !_saveFailed;
      return mayLeave;
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not finish saving. Please retry before leaving.',
        );
      }
      return false;
    } finally {
      if (!mayLeave) await resumeAfterNavigation();
    }
  }

  /// The parent resumes a retained Lecture after a canceled or failed action.
  /// Calling this on a workspace already disposed by navigation is harmless.
  Future<void> resumeAfterNavigation() async {
    if (!mounted) return;
    try {
      if (_ink.ready.value) await _ink.setActive(_view == LectureView.ink);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not resume the ink canvas. Reopen this Lecture to continue.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparingToLeave = false);
    }
  }

  Future<void> _inkAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The ink tool could not complete. Your saved notes are safe.',
        );
      }
    }
  }

  void _cancel() {
    ++_operation;
    _activeProvider?.cancel();
    _activeProvider = null;
    if (mounted) {
      setState(() {
        _generating = false;
        _connecting = false;
      });
    }
  }

  Future<void> _connect() async {
    if (_generating || _accountBusy || widget.providers.isEmpty) return;
    final provider = widget.providers[_providerIndex];
    final operation = ++_operation;
    _activeProvider = provider;
    setState(() => _connecting = true);
    try {
      await provider.connect();
      if (!await _showPlanNotice(provider, operation)) return;
      if (mounted && operation == _operation) {
        setState(() {
          _connected = true;
          _message = '${provider.name} is connected using your plan.';
        });
      }
    } on EnrichmentException catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() => _message = 'Could not connect. Please retry.');
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _connecting = false);
        _activeProvider = null;
      }
    }
  }

  Future<void> _openChatGptUsage(ChatGptSubscriptionProvider provider) async {
    try {
      await provider.openUsage();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Open chatgpt.com/settings/usage to manage StudyHub’s plan and credit limits.',
        );
      }
    }
  }

  Future<bool> _showPlanNotice(
    LectureEnrichmentProvider provider,
    int operation,
  ) async {
    if (!mounted || operation != _operation) return false;
    if (provider is! ChatGptSubscriptionProvider) return true;
    final show = await provider.needsPlanNotice;
    if (!mounted || operation != _operation) return false;
    if (!show) return true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('You’re using your ChatGPT plan'),
        content: const Text(
          'Eligible requests use your ChatGPT plan or credits according to your account settings. Manage StudyHub’s limits in ChatGPT. To use included allowance only, turn off credit fallback or set the app’s credit limit to zero if that control is available.',
        ),
        actions: [
          TextButton(
            onPressed: () => _openChatGptUsage(provider),
            child: const Text('Manage usage'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    if (!mounted || operation != _operation) return false;
    await provider.markPlanNoticeShown();
    return mounted && operation == _operation;
  }

  Future<void> _disconnect() async {
    if (_generating || _accountBusy || widget.providers.isEmpty) return;
    final provider = widget.providers[_providerIndex];
    setState(() => _disconnecting = true);
    try {
      await provider.disconnect();
      if (mounted) setState(() => _connected = false);
    } catch (error) {
      final connected = await _connectionStatus();
      if (mounted) {
        setState(() {
          _connected = connected;
          _message = error is EnrichmentException
              ? error.message
              : 'Could not disconnect. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  Future<void> _showView(LectureView view) async {
    setState(() => _view = view);
    if (_ink.ready.value) {
      try {
        await _ink.setActive(view == LectureView.ink);
      } catch (_) {
        // Editable source and saved content remain available if tools fail.
      }
    }
  }

  Future<void> _generate() async {
    if (_generating ||
        _accountBusy ||
        widget.providers.isEmpty ||
        _content == null) {
      return;
    }
    final provider = widget.providers[_providerIndex];
    final operation = ++_operation;
    setState(() {
      _generating = true;
      _message = null;
    });
    _activeProvider = provider;
    try {
      final snapshot = await _ink.captureSnapshot();
      if (snapshot.images.isEmpty) {
        throw const EnrichmentException(
          'Write some notes before creating HTML.',
        );
      }
      _changed(snapshot);
      final sourceRevision = _inkBaseRevision + snapshot.changeId;
      await _saveTail;
      if (_saveFailed) {
        throw const EnrichmentException(
          'Save your ink successfully before sending it.',
        );
      }
      if (!mounted || operation != _operation) return;
      final send = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Create HTML with ${provider.name}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.preview.isNotEmpty)
                SizedBox(
                  height: 160,
                  width: 280,
                  child: Image.memory(snapshot.preview, fit: BoxFit.contain),
                ),
              const SizedBox(height: 12),
              Text(
                '${snapshot.images.length} image${snapshot.images.length == 1 ? '' : 's'} from this Lecture, its title, and any existing text notes will be sent using your connected account.',
              ),
              const SizedBox(height: 8),
              Text(
                provider is ChatGptSubscriptionProvider
                    ? 'Your ink stays in StudyHub. This uses your ChatGPT plan or credits according to your account settings.'
                    : 'Your ink stays in StudyHub. This uses your plan allowance.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send notes'),
            ),
          ],
        ),
      );
      if (send != true || !mounted || operation != _operation) return;
      if (!await provider.isConnected) {
        await provider.connect();
      }
      if (!await _showPlanNotice(provider, operation)) return;
      if (!mounted || operation != _operation) return;
      setState(() => _connected = true);
      final result = await provider.generate(
        images: snapshot.images,
        lectureTitle: widget.lecture.title,
        sourceNotes: widget.lecture.notes,
      );
      if (!mounted || operation != _operation) return;
      final html = SafeLectureHtml.parse(result);
      final next = _content!.withHtml(
        html.document,
        sourceRevision: sourceRevision,
        provider: provider.name,
      );
      setState(() {
        _content = next;
        _html = html;
        _message = 'HTML is ready. Your ink is unchanged.';
      });
      _enqueueSave(next);
      await _saveTail;
    } on EnrichmentException catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _message = error.message);
      }
    } on FormatException {
      if (mounted && operation == _operation) {
        setState(
          () => _message = 'The assistant did not return usable HTML. Your previous notes are safe.',
        );
      }
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(
          () => _message = 'Could not create HTML. Your ink and previous HTML are safe. Please retry.',
        );
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _generating = false);
        _activeProvider = null;
      }
    }
  }

  @override
  void dispose() {
    ++_operation;
    _activeProvider?.cancel();
    _ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Could not open these notes. The existing file is preserved.',
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final content = _content;
    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final ipad = defaultTargetPlatform == TargetPlatform.iOS;
    return AbsorbPointer(
      absorbing: _preparingToLeave,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SegmentedButton<LectureView>(
                            segments: [
                              const ButtonSegment(
                                value: LectureView.ink,
                                label: Text('Ink'),
                                icon: Icon(Icons.draw_outlined),
                              ),
                              ButtonSegment(
                                value: LectureView.html,
                                label: const Text('HTML'),
                                icon: const Icon(Icons.auto_awesome_outlined),
                                enabled: content.hasHtml,
                              ),
                            ],
                            selected: {_view},
                            onSelectionChanged: (value) =>
                                _showView(value.single),
                          ),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _saveFailed
                                  ? 'Not saved'
                                  : _saving
                                  ? 'Saving…'
                                  : 'Saved',
                              style: TextStyle(
                                color: _saveFailed
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ),
                          if (_saveFailed)
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _enqueueSave(_content!),
                              child: const Text('Retry saving'),
                            ),
                          if (content.htmlIsStale)
                            const Text('HTML needs refresh'),
                          if (widget.providers.length > 1)
                            DropdownButton<int>(
                              value: _providerIndex,
                              onChanged: _generating || _accountBusy
                                  ? null
                                  : (value) async {
                                      setState(() {
                                        _providerIndex = value!;
                                        _connected = false;
                                      });
                                      final connected =
                                          await _connectionStatus();
                                      if (mounted && _providerIndex == value) {
                                        setState(() => _connected = connected);
                                      }
                                    },
                              items: [
                                for (
                                  var index = 0;
                                  index < widget.providers.length;
                                  index++
                                )
                                  DropdownMenuItem(
                                    value: index,
                                    child: Text(widget.providers[index].name),
                                  ),
                              ],
                            ),
                          if (widget.providers.isNotEmpty)
                            OutlinedButton(
                              onPressed: _generating || _accountBusy
                                  ? null
                                  : _connected
                                  ? _disconnect
                                  : _connect,
                              child: Text(
                                _disconnecting
                                    ? 'Disconnecting…'
                                    : _connecting
                                    ? 'Connecting…'
                                    : _connected
                                    ? 'Disconnect ${widget.providers[_providerIndex].name}'
                                    : widget.providers[_providerIndex]
                                          is ChatGptSubscriptionProvider
                                    ? 'Continue with ChatGPT'
                                    : 'Connect ${widget.providers[_providerIndex].name}',
                              ),
                            ),
                          if (_connected)
                            Text(
                              widget.providers[_providerIndex]
                                      is ChatGptSubscriptionProvider
                                  ? 'Using ChatGPT plan'
                                  : 'Using your plan',
                            ),
                          if (widget.providers.isNotEmpty &&
                              widget.providers[_providerIndex]
                                  is ChatGptSubscriptionProvider)
                            TextButton(
                              onPressed: () => _openChatGptUsage(
                                widget.providers[_providerIndex]
                                    as ChatGptSubscriptionProvider,
                              ),
                              child: const Text('Manage usage'),
                            ),
                          if (widget.providers.isNotEmpty)
                            ValueListenableBuilder<bool>(
                              valueListenable: _ink.ready,
                              builder: (context, ready, _) =>
                                  FilledButton.tonalIcon(
                                    onPressed:
                                        ready &&
                                            !_generating &&
                                            !_accountBusy &&
                                            !_saveFailed
                                        ? _generate
                                        : null,
                                    icon: const Icon(Icons.auto_awesome),
                                    label: Text(
                                      _generating
                                          ? 'Creating HTML…'
                                          : 'Create HTML with ${widget.providers[_providerIndex].name}',
                                    ),
                                  ),
                            ),
                          if (_generating || _connecting)
                            TextButton(
                              onPressed: _cancel,
                              child: Text(
                                _connecting
                                    ? 'Cancel connection'
                                    : 'Cancel conversion',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (ipad && _view == LectureView.ink)
                      ValueListenableBuilder<bool>(
                        valueListenable: _ink.ready,
                        builder: (context, ready, _) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: 'Undo ink',
                                onPressed: ready
                                    ? () => _inkAction(_ink.undo)
                                    : null,
                                icon: const Icon(Icons.undo),
                              ),
                              IconButton(
                                tooltip: 'Redo ink',
                                onPressed: ready
                                    ? () => _inkAction(_ink.redo)
                                    : null,
                                icon: const Icon(Icons.redo),
                              ),
                              FilterChip(
                                label: const Text('Draw with finger'),
                                selected: _fingerDrawing,
                                onSelected: ready
                                    ? (value) async {
                                        try {
                                          await _ink.setFingerDrawing(value);
                                          if (mounted) {
                                            setState(
                                              () => _fingerDrawing = value,
                                            );
                                          }
                                        } catch (_) {
                                          if (mounted) {
                                            setState(
                                              () => _message = 'Could not change the input mode.',
                                            );
                                          }
                                        }
                                      }
                                    : null,
                              ),
                              Text(
                                _fingerDrawing
                                    ? 'Draw mode · two fingers scroll'
                                    : 'Pencil writes · fingers scroll',
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(_message!),
                              ),
                            ),
                            if (_html != null && !_saveFailed)
                              TextButton(
                                onPressed: () => _showView(LectureView.html),
                                child: const Text('View HTML'),
                              ),
                            IconButton(
                              tooltip: 'Dismiss message',
                              onPressed: () => setState(() => _message = null),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    if (_generating || _accountBusy)
                      const LinearProgressIndicator(),
                    if (widget.lecture.notes.isNotEmpty)
                      ExpansionTile(
                        title: const Text('Existing text notes'),
                        children: [
                          SizedBox(
                            height: 120,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(widget.lecture.notes),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _view.index,
                children: [
                  if (ipad || widget.inkController != null)
                    InkCanvas(
                      lectureId: widget.lecture.id,
                      initialDrawing: content.drawing,
                      onChanged: _changed,
                      controller: _ink,
                    )
                  else
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text('Handwriting is available on iPad.'),
                          const SizedBox(height: 16),
                          if (content.preview != null)
                            Image.memory(content.preview!),
                          if (!content.hasInk)
                            const Text('Your notes start here.'),
                        ],
                      ),
                    ),
                  if (_html != null)
                    LectureHtmlView(
                      key: ValueKey(content.html),
                      content: _html!,
                    )
                  else
                    Center(
                      child: Text(
                        content.hasHtml
                            ? 'This HTML version could not be opened safely. Re-create it from Ink.'
                            : 'Create HTML from your ink to see it here.',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
