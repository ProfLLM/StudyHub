# Opt-in live ChatGPT quality run

This macOS-only suite lives in `integration_test/` so Flutter includes its native test plugin, and requires an explicit live or replay define. It uses the production native ChatGPT provider and isolated native HTML renderer, with six public synthetic sheets plus one ordered two-sheet request. It changes no library files and never sends the semantic expectations. Ordinary `flutter test` does not discover it. Explicitly targeting it without the opt-in define skips the case before a provider is constructed. iPad capture is tested separately.

Only run after authorization to use the learner's subscription allowance. A real native StudyHub sign-in is used if needed; no credentials are copied from another app. The harness does not collect headers, callbacks, tokens, account identifiers, or model catalog responses. Never add credentials to compile defines.

Prepare the public fixture JSON outside the repository. The host driver sends it through Flutter's existing debug-test transport; the app never reads external or container files:

```sh
python3 live_test/encode_corpus.py /private/tmp/studyhub-live-fixtures.json
STUDYHUB_LIVE_FIXTURES_FILE=/private/tmp/studyhub-live-fixtures.json \
  flutter drive -d macos \
  --driver=test_driver/provider_quality_driver.dart \
  --target=integration_test/provider_quality_test.dart \
  --dart-define=STUDYHUB_LIVE_CHATGPT=true \
  --dart-define=STUDYHUB_LIVE_COMMIT=THE_REVIEWED_COMMIT
```

The encoder writes only PNGs, titles, IDs, and hashes to the public JSON. The host driver accepts only `/private/tmp/studyhub-live-fixtures.json` or its UUID-suffixed equivalent, rejects symlinks and files larger than 2 MiB, and disables communication logging. An opt-in-only, single-use Dart service extension receives this public corpus. The test paints a waiting screen before receiving it and verifies image hashes before constructing the provider. Fixture images never enter command-line defines or production assets. No extra filesystem permission or private account access is used; credentials remain inside the actual native app. Delete the public temporary JSON when finished.

1. Press **Continue with ChatGPT** and complete the actual sign-in/approval. This interactive validation run allows 30 minutes for a sign-in attempt and 45 minutes total to establish the connection, so an asynchronous approval handoff does not expire after five minutes. An existing StudyHub Keychain connection can be reused; the harness never reads credentials outside the native app.
2. The run **stops after connection**. Open OpenAI usage settings and verify that credit spending is disabled: turn off credit fallback after plan limits (or set this app’s credit limit to **0**, if that control is offered). Do not press Start until verified. Verification in OpenAI’s account UI is required; the harness cannot prove the server-side billing configuration. If credit spending cannot be ruled out, stop the run and report it as not verified.
3. Press **Start 7 synthetic conversions** only after verification. Exactly seven requests run sequentially, with no automatic retry. Cancel stops the current provider operation; any failure stops the remaining requests. Subscription limits, refusal, timeout, or missing authentication are not quality passes.
4. The host driver writes actual raw HTML, sanitized HTML, ordered input hashes, latency, source-byte checks, and render-load results to a new ignored `build/provider-quality/<UTC run>/` directory, including partial evidence on failure. No screenshots are requested because the macOS integration screenshot plugin does not support them.
5. Review every result against [the corpus expectations](../test_fixtures/ai_quality/README.md), opening **sanitized** output for review. Raw HTML is untrusted evidence and must not be opened in an ordinary browser. Native load success alone does not establish visual quality or semantic fidelity. The report remains `returned_pending_semantic_review` until a reviewer verifies equations, units, topology, uncertainty, corrections, and ordered-pair separation. Model metadata is unknown unless independently disclosed.

This harness validates direct provider return and native rendering on macOS. Source-library attachment, stale revisions, cancellation races, real Pencil handwriting, and physical iPad behavior are separate checks; it does not claim to validate them. The service extension transports only public test inputs; account approval and the Start button remain visible user actions. There is no paid-API fallback.

## Replay saved public results without model calls

After a live run, replay its exact raw results through the current production sanitizer and native renderer. This mode constructs no provider and reads no Keychain credentials. It verifies native loading and source-byte preservation; semantic review remains a separate recorded judgment.

```sh
python3 live_test/encode_corpus.py /private/tmp/studyhub-live-fixtures.json \
  --replay-from build/provider-quality/THE_LIVE_RUN
STUDYHUB_LIVE_FIXTURES_FILE=/private/tmp/studyhub-live-fixtures.json \
  flutter drive -d macos --driver=test_driver/provider_quality_driver.dart \
  --target=integration_test/provider_quality_test.dart \
  --dart-define=STUDYHUB_REPLAY_CHATGPT=true
```

The separate `html_review.dart` entry point provides interactive native review of these public outputs. Pass a local JSON define file whose `STUDYHUB_HTML_REVIEW` value is a JSON string containing `{ "id": "case", "html": "public raw result" }` records. Run `flutter run -d macos -t live_test/html_review.dart --dart-define-from-file=/private/tmp/public-review.json`. It does not instantiate a provider or open the learner’s library. Never put private study material or credentials in this review payload.
