import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyhub/domain/lecture_assignment.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/enrichment/assignment_document.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';

LectureAssignment example() => LectureAssignment(
  id: '0123456789abcdef0123456789abcdef',
  request: 'Help me reason',
  html: '<h1>Explain the forces</h1><textarea data-answer-key="reason"></textarea>',
  sourceRevision: 0,
  provider: 'ChatGPT',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old sidecars remain readable and assignments upgrade only the sidecar',
    () async {
      final dir = await Directory.systemTemp.createTemp('studyhub-assignment-');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonLectureContentStore(dir);
      final old = LectureContent(lectureId: 'lecture');
      expect(old.toJson()['schemaVersion'], 1);
      await store.save(old);
      final withAssignment = old.withAssignment(example());
      await store.save(withAssignment);
      final reopened = await store.load('lecture');
      expect(reopened.toJson()['schemaVersion'], 2);
      expect(reopened.assignments.single.toJson(), example().toJson());
      await expectLater(store.save(old), throwsStateError);
      await store.delete('lecture');
      expect((await store.load('lecture')).assignments, isEmpty);
    },
  );
  test(
    'answers and feedback retain independent revisions and reject stale writes',
    () async {
      final dir = await Directory.systemTemp.createTemp('studyhub-answers-');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonLectureContentStore(dir);
      final answered = example().withAnswers('{"reason":"No net force"}');
      final reviewed = answered.withFeedback(
        '<p>Check the vertical forces.</p>',
        1,
      );
      final changed = reviewed.withAnswers(
        '{"reason":"Vertical forces balance"}',
      );
      expect(changed.feedbackIsStale, isTrue);
      expect(changed.answerRevision, 2);
      expect(changed.feedbackAnswerRevision, 1);
      expect(changed.html, example().html);
      await store.save(
        LectureContent(lectureId: 'lecture').withAssignment(changed),
      );
      await expectLater(
        store.save(
          LectureContent(lectureId: 'lecture').withAssignment(answered),
        ),
        throwsStateError,
      );
      expect(
        (await store.load('lecture')).assignments.single.answersJson,
        changed.answersJson,
      );
    },
  );
  test('untrusted answer payloads have shape, depth and size bounds', () {
    for (final invalid in [
      '[]',
      'null',
      '{"x":${'[' * 18}0${']' * 18}}',
      '{"x":"${'x' * LectureAssignment.maxAnswerBytes}"}',
    ]) {
      expect(() => example().withAnswers(invalid), throwsFormatException);
    }
    expect(
      () => example().withFeedback('<p>future</p>', 1),
      throwsFormatException,
    );
    expect(
      () => LectureContent.fromJson({'schemaVersion': 1.0}),
      throwsFormatException,
    );
    expect(
      () => AssignmentDocument.inkImages(
        '{"x":{"kind":"ink","png":"file:///private.png"}}',
      ),
      throwsFormatException,
    );
  });
  test('packaging puts arbitrary scripts below an opaque origin and protects the host', () async {
    final unsafe = LectureAssignment(
      id: example().id,
      request: 'x',
      sourceRevision: 0,
      provider: 'ChatGPT',
      answersJson: jsonEncode({'reason': '</script><script>escape()</script>'}),
      html: '<h1>Exercise</h1><meta http-equiv="refresh" content="0;url=https://example.invalid"><base href="https://example.invalid"><script src="https://example.invalid/a.js">studyhub.setAnswer("a",1)</script><input data-answer-key="a" onclick="escape()"><iframe src="file:///private"></iframe>',
    );
    final document = await AssignmentDocument.build(unsafe);
    final verification = Directory('build/assignment-verification');
    await verification.create(recursive: true);
    await File('${verification.path}/hostile.html').writeAsString(document);
    final interactive = LectureAssignment(
      id: example().id,
      request: 'Practice',
      sourceRevision: 0,
      provider: 'Synthetic',
      html: '''
      <h1>Practice</h1><label>Reason<textarea data-answer-key="reason"></textarea></label>
      <label><input type="radio" name="choice" value="yes" data-answer-key="choice">Yes</label>
      <canvas data-answer-key="drawing" width="600" height="250" style="width:100%;background:white" aria-label="Draw your reasoning"></canvas>
      ''',
    );
    await File('${verification.path}/interactive.html')
        .writeAsString(await AssignmentDocument.build(interactive));
    expect(document, contains('sandbox="allow-scripts"'));
    expect(document, isNot(contains('allow-same-origin')));
    expect(document, contains("connect-src 'none'"));
    expect(document, isNot(contains('</script><script>escape()')));
    expect(document, isNot(contains('src=\\"https://example.invalid')));
    expect(document, isNot(contains('onclick=')));
    expect(document, contains("e.source !== frame.contentWindow"));
    expect(document, contains('4194304'));
  });
}
