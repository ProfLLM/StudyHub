# Synthetic live-provider fidelity corpus

Six public synthetic sheets exercise equations, units, directed diagrams, corrections, and explicit uncertainty. Each has a canonical PNG for model input, an inspectable SVG source, and semantic expectations in `manifest.json`.

These are **typeset with a handwriting-style font, not actual handwriting**. They test fidelity of the enrichment roundtrip, not Pencil capture, pen recognition, or real handwriting accuracy. The separate native PKDrawing tests cover capture/export; real handwriting remains a final experience check. All scenarios and numbers are invented. No learner material or credentials are included.

| Sheet | Main quality risk |
|---|---|
| 01 Mechanics | Force directions, signs, SI units |
| 02 RC circuit | Circuit topology, micro/kilo prefixes, charging exponential |
| 03 Calculus | Derivative versus value, integral bounds, graph geometry |
| 04 Bayes | Conditional probabilities and tree branch labels |
| 05 Directed graph | Exact directed edges, BFS levels, crossed-out correction |
| 06 Uncertainty | Missing values remain uncertain; crossings versus junctions |

## Repeatable live evaluation

1. Validate assets with `python3 test_fixtures/ai_quality/validate.py` (Pillow required). Record the commit and PNG hashes from the manifest.
2. Use the actual StudyHub subscription flow for ChatGPT. Authenticate through the provider's consent screen; never reuse another app's tokens or copy credentials. Use only these synthetic PNGs. No API-billed route is part of this check.
3. For each sheet, send the PNG once with the app's production enrichment instruction, the sheet title, and **empty source notes**. Do not send the expected answers or manifest. Log the prompt version/hash and provider model if disclosed. If a provider tool requires tiling, keep order explicit and record the tiles' hashes too.
4. Store returned HTML and screenshots in a local run directory, for example `/private/tmp/studyhub-ai-quality/<run-id>/`. Keep provider credentials, headers, raw OAuth callbacks, browser state, and account identifiers out of reports. Record actual observed success/failure and latency. Do not substitute fixture output for live output.
5. Review the rendered result in the app, next to the PNG. Check **every equation semantically**, allowing equivalent MathML/notation, including units and bounds. Compare diagram node/edge sets and listed geometric invariants. Check all required statements and forbidden changes from the manifest. Inspect uncertainty and the superseded correction explicitly. A text substring match alone cannot establish correctness.
6. Confirm a complete self-contained static HTML document renders with inline SVG and MathML, legible labels and equations, no clipping at iPad width, and no network/script dependency. Native isolation tests validate the security boundary separately. Check source ink/preview remains byte-identical, HTML is attached to the intended lecture/revision, and switching between source and HTML works.
7. Run one multi-image job using sheets 01 and 02 in that order. Require clearly separated sections, no mixing of variables, correct image order, and the same expectations for both sheets. This adds one roundtrip for ChatGPT; it is not an additional distinct sheet.
8. Complete the ChatGPT report. All critical fidelity expectations must pass on all six sheets and the ordered pair. Any fabricated digit, wrong equation, lost uncertainty, or extra/missing diagram edge is a failure. Treat unsupported/unknown model metadata as unknown, not failure. Report provider refusal, limit, timeout, or missing live authorization as **not verified**, never as a quality pass. Retry at most once for a transient failure, preserving both attempts.

Suggested small live budget: **7 requests for ChatGPT**, plus at most one retry per transient failure. Use existing subscription allowances only. ChatGPT must complete its actual direct return route; manual HTML copying does not validate the roundtrip. Run a synthetic cancellation and stale-revision case separately using the normal app flow, and verify no late response is attached. Do not intentionally exhaust subscription limits.

## Acceptance and evidence

Copy `report-template.json` into the local run directory and fill it with observed evidence. Equations can be algebraically equivalent; diagram styling can change. Diagram topology, corrected facts, uncertainty, and source material must be preserved. Stylistic attractiveness is assessed alongside semantic fidelity, not used to excuse errors.

Fixtures being valid does not mean ChatGPT passed. No live provider result is checked into this directory by default, and the initial template is deliberately `not_run`.

## Regeneration

`generate.py` requires Pillow and a local font. On this workstation:

```sh
/Users/lpavel/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 test_fixtures/ai_quality/generate.py
/Users/lpavel/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 test_fixtures/ai_quality/validate.py
```

Other systems can use `python3 .../generate.py --font /path/to/local-font.ttf`. Font binaries are not distributed or embedded. SVG font fallback may change on another computer; use the supplied PNGs as fixed live inputs. Regenerating with another font changes PNG hashes and should be recorded as a new corpus revision. Geometry and generation have no random inputs.
