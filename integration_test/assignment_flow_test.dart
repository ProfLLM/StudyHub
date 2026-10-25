import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studyhub/ai/lecture_assignment_provider.dart';
import 'package:studyhub/ai/lecture_enrichment_provider.dart';
import 'package:studyhub/app/assignment_view.dart';
import 'package:studyhub/app/lecture_workspace.dart';
import 'package:studyhub/domain/library.dart';
import 'package:studyhub/domain/lecture_content.dart';
import 'package:studyhub/persistence/lecture_content_store.dart';

class _Provider
    implements LectureEnrichmentProvider, LectureAssignmentProvider {
  _Provider(this.endpoint);
  final String endpoint;
  String? reviewedAnswers;
  List<Uint8List>? reviewedImages;
  @override
  String get name => 'Synthetic ChatGPT';
  @override
  Future<bool> get isConnected async => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void cancel() {}
  @override
  Future<String> generate({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
  }) async => '<h1>Static lecture</h1>';
  @override
  Future<String> createAssignment({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
    required String request,
  }) async =>
      '''
    <h1>Synthetic force assignment</h1><label>Explain<input data-answer-key="reason" value="initial"></label>
    <select multiple data-answer-key="forces"><option value="gravity">Gravity</option><option value="normal">Normal</option><option value="friction">Friction</option></select>
    <canvas data-answer-key="drawing" width="300" height="120" style="background:white"></canvas>
    <script>
    document.addEventListener('DOMContentLoaded', async()=>{
      let denied=false;try{parent.document.body.innerHTML='escaped';}catch(e){denied=true;}
      setTimeout(()=>{
        try{webkit.messageHandlers.assignment.postMessage(JSON.stringify({type:'state',answers:'{"forged":true}'}));}catch(e){}
        studyhub.setAnswer('bridgeProbeFinished',true);
      },700);
      const previous=studyhub.getAnswer('reason');
      const select=document.querySelector('select');
      if(!studyhub.getAnswer('forces')) {
        select.options[0].selected=true;select.options[1].selected=true;
        select.dispatchEvent(new Event('input'));
      }
      studyhub.setAnswer('restoredForces',Array.from(select.selectedOptions).map(o=>o.value));
      for(const name of ['RTCPeerConnection','webkitRTCPeerConnection']) {
        let blocked=false;
        try {
          const peer=new window[name]({iceServers:[{urls:'${endpoint.replaceFirst('http:', 'stun:').replaceFirst('//', '')}'}]});
          peer.createDataChannel('probe');await peer.setLocalDescription(await peer.createOffer());
        } catch(e) {blocked=true;}
        studyhub.setAnswer(name+'Blocked',blocked);
      }
      const realm=document.createElement('iframe');document.body.append(realm);
      let childRtcBlocked=true;
      try {childRtcBlocked=typeof realm.contentWindow.RTCPeerConnection==='undefined';}catch(e){}
      studyhub.setAnswer('childRtcBlocked',childRtcBlocked);
      realm.remove();
      if(!previous) {
        const input=document.querySelector('input');input.value='Forces balance';input.dispatchEvent(new Event('input'));
        const c=document.querySelector('canvas');const ctx=c.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,300,120);ctx.fillStyle='black';ctx.fillText('F = ma',20,40);
        studyhub.setAnswer('drawing',{kind:'ink',png:c.toDataURL('image/png')});
      }
      studyhub.setAnswer('parentDenied',denied);
      try{await fetch('$endpoint/forbidden');studyhub.setAnswer('networkBlocked',false);}catch(e){studyhub.setAnswer('networkBlocked',true);}
      try{await fetch('file:///private/not-allowed');studyhub.setAnswer('fileBlocked',false);}catch(e){studyhub.setAnswer('fileBlocked',true);}
      const image=new Image();image.src='$endpoint/image';
      const link=document.createElement('link');link.rel='preconnect';link.href='$endpoint';document.head.append(link);
      const child=document.createElement('iframe');child.src='$endpoint/frame';document.body.append(child);
      try{new WebSocket('${endpoint.replaceFirst('http:', 'ws:')}/socket');}catch(e){}
      try{navigator.sendBeacon('$endpoint/beacon','no');}catch(e){}
      let storageDenied=false;try{localStorage.setItem('test','x');}catch(e){storageDenied=true;}studyhub.setAnswer('storageDenied',storageDenied);
      const a=document.createElement('a');a.href='$endpoint/navigation';a.click();
    });
    </script>''';
  @override
  Future<String> reviewAssignment({
    required List<Uint8List> images,
    required String lectureTitle,
    required String sourceNotes,
    required String assignmentHtml,
    required String answersJson,
  }) async {
    reviewedAnswers = answersJson;
    reviewedImages = images;
    return '<h1>Review of your reasoning</h1><p>Check which forces balance.</p>';
  }
}

class _RecordingStore extends JsonLectureContentStore {
  _RecordingStore(super.directory);
  bool sawForged = false;
  @override
  Future<void> save(LectureContent content) {
    if (content.assignments.any(
      (a) => a.answersJson.contains('"forged":true'),
    )) {
      sawForged = true;
    }
    return super.save(content);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native isolated assignment creates, saves, reviews ink, and reopens',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp(
        'studyhub-assignment-integration-',
      );
      final store = _RecordingStore(dir);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final udp = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      var datagrams = 0;
      udp.listen((event) {
        if (event == RawSocketEvent.read) {
          while (udp.receive() != null) {
            datagrams++;
          }
        }
      });
      var connections = 0;
      server.listen((r) {
        connections++;
        r.destroy();
      });
      final provider = _Provider('http://127.0.0.1:${server.port}');
      addTearDown(() async {
        await server.close();
        udp.close();
        await dir.delete(recursive: true);
      });
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LectureWorkspace(
                lecture: const Lecture(
                  id: 'assignment-lecture',
                  title: 'Forces',
                  notes: 'Net force determines acceleration.',
                ),
                store: store,
                providers: [provider],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> waitFor(bool Function() test) async {
        for (var i = 0; i < 160 && !test(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          test(),
          isTrue,
          reason:
              'Assignment widgets: ${find.byType(AssignmentView).evaluate().length}; '
              'error: ${find.byType(AssignmentView).evaluate().isEmpty ? "no view" : tester.widget<AssignmentView>(find.byType(AssignmentView)).controller.error.value}; '
              'platform: ${Platform.operatingSystem}',
        );
      }

      await mount();
      debugPrint('Assignment flow: mounted');
      await waitFor(() => find.text('Create assignment').evaluate().isNotEmpty);
      await tester.ensureVisible(find.text('Create assignment'));
      await tester.tap(find.text('Create assignment'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(() => find.byType(AlertDialog).evaluate().isNotEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create assignment').last,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(
        () =>
            find.byType(AssignmentView).evaluate().isNotEmpty &&
            tester
                .widget<AssignmentView>(find.byType(AssignmentView))
                .assignment
                .answersJson
                .contains('bridgeProbeFinished'),
      );
      debugPrint('Assignment flow: answers captured');
      // A ready WebKit page can still be invisible if the Flutter surface
      // collapses after its loading indicator disappears.
      final surface = find.byType(Platform.isIOS ? UiKitView : AppKitView);
      expect(tester.getSize(surface).width, greaterThan(100));
      expect(tester.getSize(surface).height, greaterThan(100));
      var saved = await store.load('assignment-lecture');
      // Let the last autosave finish before assertions and navigation.
      await tester.pump(const Duration(milliseconds: 400));
      saved = await store.load('assignment-lecture');
      final answers = jsonDecode(saved.assignments.single.answersJson) as Map;
      expect(answers['parentDenied'], true);
      expect(answers['networkBlocked'], true);
      expect(answers['fileBlocked'], true);
      expect(answers['storageDenied'], true);
      expect(answers['RTCPeerConnectionBlocked'], true);
      expect(answers['webkitRTCPeerConnectionBlocked'], true);
      expect(answers['childRtcBlocked'], true);
      expect(answers['forces'], ['gravity', 'normal']);
      expect(answers['restoredForces'], ['gravity', 'normal']);
      expect(datagrams, 0);
      expect(answers.containsKey('forged'), false);
      expect(store.sawForged, false);
      expect(answers['reason'], 'Forces balance');
      expect(
        (answers['drawing'] as Map)['png'],
        startsWith('data:image/png;base64,'),
      );
      expect(connections, 0);
      await tester.ensureVisible(find.text('Ask ChatGPT to review'));
      await tester.tap(find.text('Ask ChatGPT to review'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.reviewedAnswers, isNull);
      await waitFor(() => find.text('Send answers').evaluate().isNotEmpty);
      await tester.tap(find.text('Send answers'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(() => provider.reviewedAnswers != null);
      expect(provider.reviewedAnswers, contains('Forces balance'));
      expect(jsonDecode(provider.reviewedAnswers!)['forces'], [
        'gravity',
        'normal',
      ]);
      expect(provider.reviewedImages!.length, inInclusiveRange(1, 2));
      expect(provider.reviewedImages!.last.take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      saved = await store.load('assignment-lecture');
      debugPrint('Assignment flow: review received');
      expect(
        saved.assignments.single.feedbackHtml,
        contains('Review of your reasoning'),
      );
      final state = tester.state<LectureWorkspaceState>(
        find.byType(LectureWorkspace),
      );
      expect(await tester.runAsync(state.prepareToLeave), true);
      debugPrint('Assignment flow: saved before leaving');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      await mount();
      debugPrint('Assignment flow: reopened');
      await tester.tap(find.text('Assignments'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitFor(
        () => tester
            .widget<AssignmentView>(find.byType(AssignmentView))
            .controller
            .ready
            .value,
      );
      expect(
        (await store.load('assignment-lecture')).assignments.single.answersJson,
        contains('Forces balance'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final reopened = jsonDecode(
        (await store.load('assignment-lecture')).assignments.single.answersJson,
      );
      expect(reopened['forces'], ['gravity', 'normal']);
      expect(reopened['restoredForces'], ['gravity', 'normal']);
      expect(datagrams, 0);
      expect(connections, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
    },
    variant: TargetPlatformVariant.only(
      Platform.isMacOS ? TargetPlatform.macOS : TargetPlatform.iOS,
    ),
  );
}
