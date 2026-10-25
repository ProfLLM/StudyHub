import 'package:flutter/material.dart';

import '../ai/chatgpt_subscription_provider.dart';
import '../ai/class_generation_provider.dart';
import '../domain/library.dart';
import '../enrichment/class_draft.dart';
import 'lecture_html_view.dart';

/// Generation is a draft until the learner reviews it and saves. Closing this
/// dialog cancels the provider; no lecture or library writes occur in generation.
class ClassCreator extends StatefulWidget {
  const ClassCreator({super.key, required this.provider, required this.save});
  final LectureEnrichmentProvider provider;
  final Future<StudyLibrary> Function(ClassDraft) save;
  @override
  State<ClassCreator> createState() => _ClassCreatorState();
}

class _ClassCreatorState extends State<ClassCreator> {
  final _request = TextEditingController();
  ClassDraft? _draft;
  String? _error;
  int _lesson = 0;
  bool _generating = false;
  bool _saving = false;
  int _operation = 0;

  Future<void> _generate() async {
    if (_generating || _saving || _request.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final operation = ++_operation;
    final provider = widget.provider;
    setState(() {
      _generating = true;
      _error = null;
    });
    bool active() => mounted && operation == _operation;
    try {
      final connected = await provider.isConnected;
      if (!active()) return;
      if (!connected) await provider.connect();
      if (!active()) return;
      if (provider is ChatGptSubscriptionProvider &&
          await provider.needsPlanNotice) {
        if (!mounted || operation != _operation) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('You’re using your ChatGPT plan'),
            content: const Text(
              'Requests use your plan or credits according to your account settings. For included allowance only, turn off credit fallback or set the app’s credit limit to zero if available.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await provider.openUsage();
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = 'Open chatgpt.com/settings/usage to manage your plan and credit limits.',
                      );
                    }
                  }
                },
                child: const Text('Manage usage'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
        if (!active()) return;
        await provider.markPlanNoticeShown();
      }
      if (!active()) return;
      final result = await (provider as ClassGenerationProvider).generateClass(
        request: _request.text.trim(),
      );
      if (!active()) return;
      final draft = ClassDraft.parse(result);
      setState(() {
        _draft = draft;
        _lesson = 0;
      });
    } on EnrichmentException catch (error) {
      if (mounted &&
          (active() || error is ChatGptConnectionRecoveryException)) {
        setState(() => _error = error.message);
      }
    } on FormatException catch (error) {
      if (active()) setState(() => _error = error.message);
    } catch (_) {
      if (active()) {
        setState(
          () => _error = 'Could not create the class. Your library is unchanged. Please retry.',
        );
      }
    } finally {
      if (active()) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (_saving || _generating || draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final library = await widget.save(draft);
      if (mounted) Navigator.pop(context, library);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancelGeneration() {
    ++_operation;
    widget.provider.cancel();
    setState(() => _generating = false);
  }

  @override
  void dispose() {
    ++_operation;
    if (_generating) widget.provider.cancel();
    _request.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final recovery =
        widget.provider is ChatGptSubscriptionProvider &&
        (widget.provider as ChatGptSubscriptionProvider)
            .connectionRecoveryRequired;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: MediaQuery.sizeOf(context).height * .88,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  draft == null ? 'Create class with ChatGPT' : draft.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (_generating || _saving) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Expanded(
                  child: draft == null
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'What would you like to learn? Include your starting level, goals, and any topics or examples you want covered.',
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _request,
                                onChanged: (_) => setState(() {}),
                                enabled: !_generating,
                                maxLines: 6,
                                maxLength: 8000,
                                decoration: const InputDecoration(
                                  labelText: 'Your learning goals',
                                  hintText: 'Teach me classical mechanics from the beginning. I know algebra but want intuition, visual explanations and worked problems.',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'ChatGPT will create up to 12 complete lectures. You can read every lesson before saving the class.',
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Only this description is sent. Your existing classes and notes are not included. This is one generation request and uses your ChatGPT plan or credits according to your account settings.',
                              ),
                              if (_generating)
                                const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Writing the lessons… This may take a few minutes.',
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${draft.lessons.length} populated lectures · Preview before saving',
                            ),
                            const SizedBox(height: 8),
                            DropdownButton<int>(
                              value: _lesson,
                              isExpanded: true,
                              items: [
                                for (final (index, lesson)
                                    in draft.lessons.indexed)
                                  DropdownMenuItem(
                                    value: index,
                                    child: Text(
                                      '${index + 1}. ${lesson.title}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _lesson = value!),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: LectureHtmlView(
                                key: ValueKey(_lesson),
                                content: draft.lessons[_lesson].content,
                              ),
                            ),
                          ],
                        ),
                ),
                if (_error != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 130),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (recovery)
                  TextButton(
                    onPressed: _generating || _saving
                        ? null
                        : () async {
                            try {
                              await widget.provider.disconnect();
                              if (mounted) setState(() => _error = null);
                            } catch (_) {}
                          },
                    child: const Text('Disconnect ChatGPT'),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    if (_generating)
                      TextButton(
                        onPressed: _cancelGeneration,
                        child: const Text('Cancel generation'),
                      ),
                    if (draft != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _draft = null;
                                _error = null;
                              }),
                        child: const Text('Change request'),
                      ),
                    if (draft == null)
                      FilledButton(
                        onPressed:
                            _generating ||
                                recovery ||
                                _request.text.trim().isEmpty
                            ? null
                            : _generate,
                        child: const Text('Generate class'),
                      )
                    else
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving class…' : 'Save class'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
