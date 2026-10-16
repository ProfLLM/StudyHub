import 'package:flutter/material.dart';

import '../domain/library.dart';
import '../persistence/library_store.dart';

class StudyHubApp extends StatelessWidget {
  const StudyHubApp({super.key, required this.openStore});

  final Future<LibraryStore> Function() openStore;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StudyHub',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff456554)),
      scaffoldBackgroundColor: const Color(0xfffafaf7),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: LibraryScreen(openStore: openStore),
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.openStore});

  final Future<LibraryStore> Function() openStore;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryStore? _store;
  StudyLibrary? _library;
  String? _classId;
  String? _lectureId;
  bool _busy = false;
  bool _loadFailed = false;

  StudyClass? get _selectedClass {
    for (final studyClass in _library?.classes ?? <StudyClass>[]) {
      if (studyClass.id == _classId) return studyClass;
    }
    return null;
  }

  Lecture? get _selectedLecture {
    for (final lecture in _selectedClass?.lectures ?? <Lecture>[]) {
      if (lecture.id == _lectureId) return lecture;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final store = await widget.openStore();
      final library = await store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _library = library;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<bool> _save(StudyLibrary library) async {
    setState(() => _busy = true);
    try {
      await _store!.save(library);
      if (!mounted) return false;
      setState(() => _library = library);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save. Your change was not applied. Try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askTitle(String kind, {String? current}) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TitleDialog(kind: kind, current: current),
      );

  Future<bool> _confirmDelete(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "$title"?'),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _newClass() async {
    final title = await _askTitle('class');
    if (title == null || !mounted) return;
    final studyClass = StudyClass(id: newId(), title: title);
    if (await _save(
      StudyLibrary(classes: [..._library!.classes, studyClass]),
    )) {
      setState(() {
        _classId = studyClass.id;
        _lectureId = null;
      });
    }
  }

  Future<void> _classAction(StudyClass studyClass, String action) async {
    if (action == 'rename') {
      final title = await _askTitle('class', current: studyClass.title);
      if (title == null || !mounted) return;
      await _save(
        StudyLibrary(
          classes: [
            for (final item in _library!.classes)
              item.id == studyClass.id ? item.copyWith(title: title) : item,
          ],
        ),
      );
    } else {
      if (!await _confirmDelete(
            studyClass.title,
            'This deletes the class, its lectures, and their notes. This cannot be undone.',
          ) ||
          !mounted) {
        return;
      }
      if (await _save(
        StudyLibrary(
          classes: _library!.classes
              .where((item) => item.id != studyClass.id)
              .toList(),
        ),
      )) {
        if (_classId == studyClass.id) {
          setState(() {
            _classId = null;
            _lectureId = null;
          });
        }
      }
    }
  }

  Future<void> _newLecture() async {
    final studyClass = _selectedClass!;
    final title = await _askTitle('lecture');
    if (title == null || !mounted) return;
    await _replaceClass(
      studyClass.copyWith(
        lectures: [
          ...studyClass.lectures,
          Lecture(id: newId(), title: title),
        ],
      ),
    );
  }

  Future<bool> _replaceClass(StudyClass replacement) => _save(
    StudyLibrary(
      classes: [
        for (final item in _library!.classes)
          item.id == replacement.id ? replacement : item,
      ],
    ),
  );

  Future<void> _lectureAction(Lecture lecture, String action) async {
    final studyClass = _selectedClass!;
    if (action == 'rename') {
      final title = await _askTitle('lecture', current: lecture.title);
      if (title == null || !mounted) return;
      await _replaceClass(
        studyClass.copyWith(
          lectures: [
            for (final item in studyClass.lectures)
              item.id == lecture.id ? item.renamed(title) : item,
          ],
        ),
      );
    } else {
      if (!await _confirmDelete(
            lecture.title,
            'This deletes the lecture and its notes. This cannot be undone.',
          ) ||
          !mounted) {
        return;
      }
      if (await _replaceClass(
        studyClass.copyWith(
          lectures: studyClass.lectures
              .where((item) => item.id != lecture.id)
              .toList(),
        ),
      )) {
        if (_lectureId == lecture.id) setState(() => _lectureId = null);
      }
    }
  }

  Widget _menu(String kind, String title, ValueChanged<String> onSelected) =>
      PopupMenuButton<String>(
        tooltip: '$kind actions: $title',
        enabled: !_busy,
        onSelected: onSelected,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  Widget _sidebar() => Material(
    color: const Color(0xffeff2eb),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 4),
          child: Text(
            'StudyHub',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Text('A little room to learn.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _newClass,
            icon: const Icon(Icons.add),
            label: const Text('New class'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 8),
          child: Text(
            'CLASSES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Expanded(
          child: _library!.classes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Your classes will appear here.'),
                )
              : ListView.builder(
                  itemCount: _library!.classes.length,
                  itemBuilder: (context, index) {
                    final studyClass = _library!.classes[index];
                    return ListTile(
                      selected: studyClass.id == _classId,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        studyClass.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${studyClass.lectures.length} lectures'),
                      onTap: _busy
                          ? null
                          : () {
                              setState(() {
                                _classId = studyClass.id;
                                _lectureId = null;
                              });
                              if (Scaffold.of(context).isDrawerOpen) {
                                Navigator.pop(context);
                              }
                            },
                      trailing: _menu(
                        'Class',
                        studyClass.title,
                        (action) => _classAction(studyClass, action),
                      ),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.save_outlined, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stored on this Mac',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _content() {
    final studyClass = _selectedClass;
    final lecture = _selectedLecture;
    if (studyClass == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_stories_outlined, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Make space for your next idea.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Create a class, add lectures, and open a notes canvas.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _newClass,
                icon: const Icon(Icons.add),
                label: const Text('Create a class'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _classId = null;
                        _lectureId = null;
                      }),
                child: const Text('Classes'),
              ),
              const Icon(Icons.chevron_right, size: 16),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _lectureId = null),
                child: Text(studyClass.title),
              ),
              if (lecture != null) ...[
                const Icon(Icons.chevron_right, size: 16),
                const Text('Notes'),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  lecture?.title ?? studyClass.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              if (lecture == null)
                FilledButton.icon(
                  onPressed: _busy ? null : _newLecture,
                  icon: const Icon(Icons.add),
                  label: const Text('New lecture'),
                )
              else
                _menu(
                  'Lecture',
                  lecture.title,
                  (action) => _lectureAction(lecture, action),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Text(
            lecture == null
                ? 'Lectures · ${studyClass.lectures.length}'
                : 'Notes canvas · Preview',
          ),
        ),
        Expanded(
          child: lecture != null ? _canvas(lecture) : _lectures(studyClass),
        ),
      ],
    );
  }

  Widget _lectures(StudyClass studyClass) {
    if (studyClass.lectures.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No lectures yet. Add your first lecture above.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      itemCount: studyClass.lectures.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final lecture = studyClass.lectures[index];
        return Card.outlined(
          color: Colors.white,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: const Icon(Icons.article_outlined),
            title: Text(lecture.title),
            subtitle: const Text('Open notes canvas'),
            onTap: _busy ? null : () => setState(() => _lectureId = lecture.id),
            trailing: _menu(
              'Lecture',
              lecture.title,
              (action) => _lectureAction(lecture, action),
            ),
          ),
        );
      },
    );
  }

  Widget _canvas(Lecture lecture) => Container(
    margin: const EdgeInsets.fromLTRB(28, 0, 28, 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffdfe4da)),
    ),
    child: SizedBox.expand(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: lecture.notes.isNotEmpty
            ? SelectableText(lecture.notes)
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_note, size: 32, color: Color(0xff71806e)),
                  SizedBox(height: 20),
                  Text(
                    'Your notes start here.',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'This is a placeholder canvas. Editing and rich content will come later.',
                    style: TextStyle(color: Color(0xff596456), height: 1.6),
                  ),
                ],
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'Could not open your library.',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Check file permissions and the JSON format. The existing file has been preserved.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    if (_library == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Scaffold(
          appBar: compact ? AppBar(title: const Text('StudyHub')) : null,
          drawer: compact ? Drawer(child: SafeArea(child: _sidebar())) : null,
          body: SafeArea(
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Row(
                    children: [
                      if (!compact) SizedBox(width: 260, child: _sidebar()),
                      Expanded(child: _content()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.kind, this.current});

  final String kind;
  final String? current;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _controller = TextEditingController(text: widget.current);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.current == null ? 'New ${widget.kind}' : 'Rename ${widget.kind}',
    ),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 360,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a name.' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.current == null ? 'Create' : 'Save'),
      ),
    ],
  );
}
