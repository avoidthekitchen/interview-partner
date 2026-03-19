# Mobile Transcription EOU + Diarization Implementation Plan

## Overview
Improve live transcript turn finalization and speaker labeling in the iOS app without taking an unnecessary big-bang rewrite. The rollout starts with deterministic replay/eval infrastructure, then upgrades live turn boundaries with streaming VAD, then strengthens final speaker labels with an offline diarization pass, and only later considers dependency or ASR-surface changes that carry higher integration risk.

## Current State Analysis
- Live turns are emitted from `StreamingEouAsrManager` string callbacks in `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`.
- New turn text is derived from a cumulative-string prefix diff, which is fragile when earlier tokens revise.
- Live speaker attribution is inferred from Sortformer overlap against estimated windows derived from `previousBoundary -> audioDuration - eouDebounce`.
- The app has provisional vs final speaker-label semantics already, but the final reconciliation still uses the same live diarization timeline rather than a stronger second pipeline.
- The pinned FluidAudio revision already includes `VadManager`, `OfflineDiarizerManager`, and `StreamingAsrManager`, so VAD and offline diarization can be planned without a dependency bump.
- The repo currently has no services test target, no committed audio fixtures, and no automated EOU/diarization benchmark harness.
- Current privacy copy promises that audio stays on-device and no audio files are retained after session end unless explicitly opted into, so any temporary audio retention must be short-lived, on-device, and documented.

## Desired End State
- Live turn start/end times are driven by actual speech windows rather than debounce-only estimates.
- Live speaker labels remain provisional but are attached to real utterance windows.
- Final persisted/exported speaker labels come from a stronger post-stop reconciliation pass using temporary on-device session audio.
- The repo contains a repeatable local benchmark that replays fixture sessions and outputs machine-readable metrics for:
  - turn-boundary error
  - late-finalization delay
  - split/merge error counts
  - live speaker-label accuracy / `Unclear` rate
  - post-stop speaker-label accuracy
  - offline reconciliation runtime
- Every implementation phase has a benchmark gate and explicit no-regression criteria against a checked-in baseline report.

## What We're NOT Doing
- Role inference or speaker enrollment (`Interviewer` vs `Participant`) in this plan.
- Word-level speaker attribution inside a single utterance.
- Remote/cloud diarization or any server-side processing.
- A full migration to `StreamingAsrManager` unless earlier phases do not sufficiently improve the metrics.
- Retaining session audio beyond the short-lived post-stop reconciliation window.

## Implementation Approach
Use the lowest-risk path that still creates durable learning:
1. Extract replayable transcription/attribution logic and build the eval harness first.
2. Keep `StreamingEouAsrManager` for live text, but insert VAD-based utterance boundaries so turn timing stops depending on debounce alone.
3. Preserve the existing provisional/final label model, but upgrade the final path to use offline diarization from a temporary local audio file.
4. Only then benchmark dependency/config changes, because without a stable harness it is impossible to tell whether those changes help.
5. Treat `StreamingAsrManager` migration as an escalation path, not the default starting point.

Assumptions to implement against:
- Temporary session audio may be retained locally until `endSession()` finishes reconciliation, then deleted by default.
- Live labels remain `Speaker A` / `Speaker B` during capture for now.
- Benchmark fixture audio will be consented synthetic or internal sample sessions, never production interview recordings.

## Phase 1: Replay Harness + Baseline Metrics

### Overview
Create deterministic evaluation infrastructure before changing the live pipeline so every later phase can prove whether EOU turn finalization and diarization actually improved.

### Changes Required
#### 1. Add a services test target and reusable evaluation module
**File**: `Packages/InterviewPartnerServices/Package.swift`
**Changes**:
- [ ] Add a `testTarget` for `InterviewPartnerServicesTests` with resource support for fixture JSON/audio files.
- [ ] Add an executable target such as `InterviewPartnerTranscriptionEvalCLI` so benchmark runs can emit JSON/Markdown reports outside a test runner.
- [ ] Keep the eval target isolated from UI concerns so it can run on macOS in local automation.

    ```swift
    .testTarget(
        name: "InterviewPartnerServicesTests",
        dependencies: ["InterviewPartnerServices"],
        resources: [.process("Resources")]
    )
    ```

#### 2. Extract pure logic from the live service into replayable components
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/TranscriptDeltaAccumulator.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/TurnAttributionModels.swift`
**Changes**:
- [ ] Move cumulative-transcript diffing, turn-window attribution, and reconciliation helpers into pure types that can be exercised without `AVAudioEngine`.
- [ ] Introduce a fixture-friendly input model for transcript callbacks, diarization segments, optional VAD events, and expected turns.
- [ ] Leave `DefaultTranscriptionService` as the orchestrator, but remove phase-specific scoring logic from it.

    ```swift
    struct ReplayFrame: Codable, Sendable {
        var elapsedSeconds: Double
        var cumulativeTranscript: String?
        var diarizationSegments: [DiarizedSegment]
        var vadEvent: VadBoundaryEvent?
    }
    ```

#### 3. Add committed fixture corpus and a benchmark reporter
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/baseline_short_ack.json`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/overlap_repair.json`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/two_speaker_pause.wav`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift`
**File**: `rpi/evals/mobile_transcription/baseline_metrics.json`
**Changes**:
- [ ] Define a small but representative fixture set covering backchannels, pauses, early-token revisions, overlap, and diarization ambiguity.
- [ ] Check in baseline expectations and a report format that records metric names, counts, and threshold status.
- [ ] Store the initial baseline report under `rpi/evals/mobile_transcription/` so later phases compare against a stable target.

    ```json
    {
      "fixture_id": "baseline_short_ack",
      "metrics": {
        "turn_boundary_mae_ms": 0,
        "late_finalization_p95_ms": 0,
        "split_merge_error_count": 0,
        "live_speaker_accuracy": 0,
        "final_speaker_accuracy": 0,
        "unclear_rate": 0
      }
    }
    ```

#### 4. Add automated tests for scoring and no-regression gates
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/TranscriptionEvaluationTests.swift`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/TurnAttributionTests.swift`
**Changes**:
- [ ] Add unit tests for delta extraction, turn-window overlap matching, split/merge scoring, and report parsing.
- [ ] Add a regression test that fails when benchmark output exceeds the checked-in tolerance envelope.
- [ ] Add a README section documenting the benchmark command used after every phase.

### Success Criteria
#### Automated Verification
- [ ] Package tests pass: `swift test --package-path Packages/InterviewPartnerServices`
- [ ] Workspace tests still pass: `xcodebuild test -workspace InterviewPartner.xcworkspace -scheme InterviewPartner -destination 'platform=iOS Simulator,name=iPhone 15'`
- [ ] Benchmark report generates successfully: `swift run --package-path Packages/InterviewPartnerServices InterviewPartnerTranscriptionEvalCLI --fixture-set baseline --output rpi/evals/mobile_transcription/latest.json`
- [ ] Baseline tolerances are checked in and enforced by tests.

#### Manual Verification
- [ ] Fixture report is readable enough to answer “did EOU improve?” and “did speaker labeling improve?” without inspecting raw logs.
- [ ] Fixture set includes at least one case for each known failure mode from the research memo.

---

## Phase 2: VAD-Grounded Live Turn Boundaries

### Overview
Keep the existing live ASR surface, but use streaming VAD to define utterance windows so live turns stop depending on `audioDuration - debounce` as their inferred end time.

### Changes Required
#### 1. Add a streaming VAD boundary engine
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/VadBoundaryTracker.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Load and reset `VadManager` alongside ASR and live diarization.
- [ ] Feed the audio tap into VAD in parallel with ASR and diarization.
- [ ] Track `speechStart` / `speechEnd` events and expose a “best current utterance window” for turn finalization.
- [ ] Fall back to the old debounce-based estimator only when VAD is unavailable or incomplete.

    ```swift
    struct UtteranceWindow: Sendable {
        let startSeconds: Double
        let endSeconds: Double
        let source: BoundarySource
    }
    ```

#### 2. Update finalized-turn assembly to use VAD windows
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/LiveTurnAssembler.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Replace `attributeNextTurn(eouDebounceMs:)` with a turn assembly path that takes VAD-derived start/end times.
- [ ] Continue using `StreamingEouAsrManager` EOU callbacks as the text-finalization signal for phase 2.
- [ ] Detect and log cases where ASR finalization arrives without a matching `speechEnd` so those misses appear in the benchmark report.
- [ ] Preserve gap detection, but base it on speech windows rather than last assigned debounce boundary.

#### 3. Extend the benchmark to score VAD-aware boundaries
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/VadBoundaryTrackerTests.swift`
**Changes**:
- [ ] Add metrics for turn-boundary mean absolute error, p95 late finalization, and split/merge count against annotated utterance windows.
- [ ] Add replay fixtures with VAD events and audio-backed cases that exercise short acknowledgements and long intra-turn pauses.
- [ ] Fail the phase if VAD integration regresses diarization accuracy or increases duplication.

### Success Criteria
#### Automated Verification
- [ ] Phase 1 benchmark command still runs on the same fixture set.
- [ ] `turn_boundary_mae_ms` and `late_finalization_p95_ms` improve versus the Phase 1 baseline on the benchmark corpus.
- [ ] `split_merge_error_count` does not regress on any fixture.
- [ ] Package and workspace tests still pass.

#### Manual Verification
- [ ] Short acknowledgements no longer get routinely merged into the previous speaker turn.
- [ ] Visible live-turn timing feels tighter without creating obvious early cuts mid-sentence.

---

## Phase 3: Offline Diarization Reconciliation From Temporary Session Audio

### Overview
Keep provisional live labels for in-session readability, but compute the durable speaker labels from a stronger post-stop offline diarization pass over temporary on-device session audio.

### Changes Required
#### 1. Capture temporary session audio during recording
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/SessionAudioCapture.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Add a local-only audio writer that records the session mic stream to a temporary WAV/CAF file.
- [ ] Start capture with the live session and stop capture before reconciliation begins.
- [ ] Guarantee best-effort deletion on success, failure, and cancellation paths.
- [ ] Keep the temp-file path out of persistent session storage unless a future explicit opt-in feature needs it.

#### 2. Reconcile finalized turns with `OfflineDiarizerManager`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/OfflineDiarizationReconciler.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Prepare offline diarization models on demand and run the offline pass during `stop()`.
- [ ] Re-label finalized turns using the VAD-grounded turn windows from Phase 2.
- [ ] Preserve live provisional labels in memory/UI during capture, but mark persisted/exported labels as final only after offline reconciliation completes.
- [ ] Define a fallback path that keeps live reconciled labels if offline diarization fails or exceeds a runtime limit.

    ```swift
    struct FinalSpeakerReconciliationResult: Sendable {
        var turns: [TranscriptTurn]
        var runtimeSeconds: Double
        var usedOfflineDiarization: Bool
    }
    ```

#### 3. Update privacy/disclosure copy for temporary retention semantics
**File**: `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/PrivacyDisclosureFeature.swift`
**File**: `README.md`
**File**: `docs/interview-partner-prd-v2.md`
**Changes**:
- [ ] Update the disclosure text to explain that temporary local audio may exist only until the session’s on-device finalization completes.
- [ ] Keep the product guarantee that audio is not uploaded and is deleted by default after finalization.
- [ ] Document benchmark/runtime expectations for the offline pass.

#### 4. Extend the benchmark for live-vs-final speaker scoring
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/SpeakerMetrics.swift`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/OfflineDiarizationReconcilerTests.swift`
**Changes**:
- [ ] Score provisional live labels and final offline labels separately.
- [ ] Record `unclear_rate`, final speaker accuracy, and offline runtime/real-time factor in the report.
- [ ] Add a no-regression threshold so final labels must beat or match Phase 2 on speaker accuracy before this phase ships.

### Success Criteria
#### Automated Verification
- [ ] Benchmark report includes both live and final speaker metrics.
- [ ] `final_speaker_accuracy` improves versus Phase 2 on the benchmark corpus.
- [ ] `offline_runtime_rtf` stays within the agreed threshold for target hardware.
- [ ] Temp audio files are deleted in automated tests after reconciliation/failure paths.

#### Manual Verification
- [ ] During capture, the UI still behaves like today with provisional labels.
- [ ] After ending a session, review/export uses improved final labels without leaving audio artifacts behind.

---

## Phase 4: Sortformer Tuning and FluidAudio Dependency Benchmark

### Overview
Use the benchmark harness to evaluate whether Sortformer config changes or a FluidAudio bump materially improve diarization quality without destabilizing the app.

### Changes Required
#### 1. Parameterize diarization config selection
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/DiarizationTuning.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Extract Sortformer config/post-processing defaults into a single tuning surface rather than hardcoding `.default`.
- [ ] Support benchmark variants for the pinned revision’s available configs and post-processing thresholds.
- [ ] Keep production default unchanged until the benchmark identifies a winner.

#### 2. Benchmark a FluidAudio revision bump separately from config-only changes
**File**: `Packages/InterviewPartnerServices/Package.swift`
**File**: `rpi/evals/mobile_transcription/variant_results/`
**Changes**:
- [ ] Run the harness against the pinned revision plus a candidate newer revision that exposes improved Sortformer presets.
- [ ] Record build/startup/runtime regressions separately from diarization accuracy.
- [ ] Land the dependency bump only if benchmark results and packaging stability are both acceptable.

#### 3. Add comparison reporting
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BenchmarkComparison.swift`
**File**: `rpi/evals/mobile_transcription/README.md`
**Changes**:
- [ ] Emit side-by-side variant comparisons for current default, tuned pinned config, and bumped dependency config.
- [ ] Define a single “recommended production config” artifact checked into the repo after the benchmark decision.

### Success Criteria
#### Automated Verification
- [ ] Variant benchmark report runs for all tested configs.
- [ ] Selected production config improves final speaker metrics or clearly reduces `Unclear` rate with no material boundary regression.
- [ ] If a dependency bump is chosen, workspace build/tests still pass on the app scheme.

#### Manual Verification
- [ ] Startup cost, memory pressure, and live-session responsiveness remain acceptable on target devices.
- [ ] The chosen config decision is backed by checked-in benchmark evidence, not anecdotal listening.

---

## Phase 5: `StreamingAsrManager` Migration (Only If Needed)

### Overview
If the Phase 2-4 improvements still leave unacceptable EOU quality, replace the string-diff EOU path with token-timed streaming ASR updates.

### Changes Required
#### 1. Introduce a lower-level live transcription pipeline
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/StreamingAsrPipeline.swift`
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift`
**Changes**:
- [ ] Add a `StreamingAsrManager`-based pipeline that keeps volatile and confirmed transcript state separately.
- [ ] Use token timings plus VAD windows to assemble turns instead of cumulative-string prefix diffs.
- [ ] Keep the existing `TranscriptionService` event surface stable for `ActiveSessionFeature`.

#### 2. Update the eval harness for token-level scoring
**File**: `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TokenAlignmentMetrics.swift`
**File**: `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/StreamingAsrPipelineTests.swift`
**Changes**:
- [ ] Add token-timing assertions and revised duplication/revision metrics.
- [ ] Compare the new pipeline against the best previous phase using the same fixture set.

### Success Criteria
#### Automated Verification
- [ ] Token-timed pipeline beats the best previous phase on boundary metrics and duplicate-text regressions.
- [ ] Existing feature-level behavior stays compatible with `ActiveSessionFeature` and `SessionReviewFeature`.

#### Manual Verification
- [ ] Live partials remain readable and stable.
- [ ] The migration is clearly worth the added complexity based on benchmark data.

## Testing Strategy
### Unit Tests
- Score cumulative transcript diff behavior, including revised earlier text.
- Score VAD boundary tracking with synthetic `speechStart` / `speechEnd` event sequences.
- Score dominant-speaker attribution over exact turn windows.
- Score offline reconciliation fallback behavior when the offline pass fails or times out.
- Score temp-audio deletion guarantees on success and failure paths.

### Integration Tests
- Replay fixture sessions end-to-end through the extracted transcription pipeline and assert report metrics.
- Run app/workspace tests to confirm that active-session capture, stop/finalize, and review/export flows still work.
- Add at least one smoke path that starts a session, appends turns, ends the session, and verifies final labels are persisted as non-provisional.

### Manual Testing Steps
1. Run the benchmark harness and save the current report as the phase baseline.
2. Start a live session in the app and speak a script with short acknowledgements, pauses, and overlapping handoff moments.
3. Confirm live turns finalize with tighter timing and that provisional labels still render.
4. End the session and verify final labels improve in the review screen.
5. Confirm no temp audio remains on disk after finalization completes.

## Performance Considerations
- Run VAD, live diarization, and ASR on the same audio tap without blocking the audio thread; keep heavy work off the main actor.
- Keep the benchmark harness small enough for frequent local runs, but representative enough to catch regressions.
- Track offline diarization runtime explicitly; if the offline pass is too slow on target hardware, it needs a guardrail or phased rollout.
- Avoid retaining full raw audio in memory during benchmark replay; stream from disk where possible.

## Migration Notes
- Phase 1 should establish the benchmark file format and baseline report before any algorithm change lands.
- Phase 3 changes the product’s privacy semantics from “no audio file ever exists” to “short-lived local temp audio exists until on-device finalization completes”; docs and disclosure must ship together with that phase.
- Phase 4 dependency bumps should happen in isolated commits from config-only tuning so regressions are attributable.
- Phase 5 should remain gated behind benchmark evidence; do not start it by default once Phase 4 finishes.
