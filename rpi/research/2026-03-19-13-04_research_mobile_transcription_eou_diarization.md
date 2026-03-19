---
date: 2026-03-19T13:04:11-07:00
researcher: Jason Wu / Codex
topic: "Mobile transcription improvements for EOU turn finalization and speaker diarization"
tags: [research, mobile, transcription, eou, diarization, fluidaudio, swift-scribe]
status: complete
---

# Research: Mobile transcription improvements for EOU turn finalization and speaker diarization

## Research Question
Identify likely ways to improve the mobile app's live transcription quality, specifically:
- better end-of-utterance turn finalization
- better speaker diarization and speaker labeling during transcription

The research should cover this repo's current implementation, the FluidAudio SDK, the `swift-scribe` example app, and external upstream/web sources where useful.

## Summary
The biggest current limitation is structural: Interview Partner's live transcript turns are created from `StreamingEouAsrManager` string callbacks, while speaker labels are inferred later from a separate Sortformer timeline. That means the app does not have native word/turn timestamps or native speaker IDs at the point where it finalizes turns, so it estimates turn windows from `previousBoundary -> audioDuration - debounce` and then assigns the dominant overlapping speaker segment (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:327`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:340`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:491`).

The strongest near-term improvement is to add a real speech-boundary layer using FluidAudio's streaming VAD and use that to drive utterance start/end times. FluidAudio already exposes `speechStart` / `speechEnd` streaming events with configurable hysteresis and padding, but the app does not use them today (`https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadManager+Streaming.swift#L10-L27`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadManager+Streaming.swift#L57-L90`).

For speaker labeling, the best improvement is dual-phase diarization:
- keep provisional live labels for in-session readability
- run a stronger post-stop diarization reconciliation pass from temporary session audio before persisting/exporting final labels

FluidAudio already ships both `OfflineDiarizerManager` and the older `DiarizerManager` batch pipeline, and `swift-scribe` already uses the "record now, diarize after stop" pattern (`https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L127-L129`, `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/DiarizationManager.swift#L88-L125`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift#L98-L123`).

## Detailed Findings

### 1. Current turn finalization is based on cumulative transcript diffs, not speech boundaries
- `DefaultTranscriptionService` wires `StreamingEouAsrManager.setPartialCallback` and `setEouCallback`, both of which only provide transcript strings; there is no native timestamp or speaker metadata on the callback surface used here (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:259`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:262`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:268`).
- The service derives "new text" by checking whether the new cumulative transcript starts with `lastCommittedTranscript`; if that prefix assumption fails, it treats the whole transcript as new text (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:428`).
- Upstream FluidAudio still exposes `EouCallback = (String) -> Void` and `PartialCallback = (String) -> Void` on `main` as of March 19, 2026, so the limitation is not just this repo's wrapper; the high-level EOU manager still gives transcript strings, not turn objects (`https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/ASR/Streaming/StreamingEouAsrManager.swift#L151-L157`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/ASR/Streaming/StreamingEouAsrManager.swift#L235-L244`).
- Interview Partner currently sets `eouDebounceMs = 640` and then estimates turn end time as `audioDuration - debounce`. That makes turn timing sensitive to silence debounce rather than actual speech boundaries (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:96`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:342`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:498`).

Why this matters:
- short acknowledgements and backchannels can get merged into a neighboring turn
- earlier-token revisions can break the prefix-diff assumption and duplicate text
- speaker attribution is forced to work from inferred windows instead of real speech windows

Likely improvement:
- add a VAD-driven utterance tracker and finalize turns on `speechEnd` or on `speechEnd + ASR confirmation`, rather than treating the EOU debounce alone as the turn boundary

### 2. Current live speaker attribution is a heuristic overlap matcher over inferred windows
- When the app finalizes a turn, it asks `LiveDiarizationEngine.attributeNextTurn(eouDebounceMs:)` for a provisional speaker label (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:340`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:342`).
- That path computes the turn window as:
  - start = previous finalized boundary
  - end = current audio duration minus EOU debounce
  (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:617`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:619`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:627`).
- It then assigns the speaker with the largest overlap in that window, falling back to `Unclear` when overlap is weak or contested (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:519`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:537`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:552`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:563`).
- The app already knows these labels are provisional: `speakerLabelIsProvisional` is stored on every turn and cleared only after end-of-session reconciliation (`Packages/InterviewPartnerDomain/Sources/InterviewPartnerDomain/SessionModels.swift:31`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:377`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:423`, `Packages/InterviewPartnerData/Sources/InterviewPartnerData/SwiftDataSessionRepository.swift:201`).

Why this matters:
- diarization can be "good enough" while the turn window is wrong, and the app will still mislabel the turn
- long pauses inside a turn window reduce confidence and increase `Unclear`
- overlap between speakers is handled only at whole-turn level, not word or sub-phrase level

Likely improvement:
- preserve the current provisional-label UX, but move from "previous boundary to estimated end" windows to actual speech windows produced by streaming VAD

### 3. FluidAudio already has the building blocks for better EOU segmentation
- FluidAudio ships streaming VAD with explicit `speechStart` / `speechEnd` events, a speech padding parameter, and hysteresis between positive and negative thresholds (`https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadTypes.swift#L24-L45`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadTypes.swift#L83-L90`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadManager+Streaming.swift#L57-L90`).
- Interview Partner does not currently use `VadManager` at all; the live audio tap feeds only `StreamingEouAsrManager` and `LiveDiarizationEngine` (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:300`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:305`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:812`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:815`).
- FluidAudio also exposes a lower-level `StreamingAsrManager` that returns `StreamingTranscriptionUpdate` objects with `tokenTimings`, `isConfirmed`, and token IDs, which is a much better surface if the app wants word- or token-timed alignment instead of string diffs (`https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift#L451-L458`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift#L746-L785`).

Implication:
- the simplest upgrade path is VAD + existing EOU manager
- the stronger long-term path is VAD + lower-level streaming ASR with token timings

### 4. The app's current post-stop reconciliation is only a stronger pass over the same live timeline, not a different diarization pipeline
- On stop, the app finalizes the live Sortformer timeline and re-runs `DominantSpeakerMatcher` over final segments (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:188`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:191`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:400`).
- That improves confidence somewhat, but it still depends on the same turn windows and the same live diarization source.
- The app does not currently record session audio to a temporary file for end-of-session reprocessing (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:294`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:315`).

By contrast:
- `swift-scribe` writes audio to disk while recording, then runs diarization after recording stops (`https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L181-L191`, `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L231-L236`, `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L295-L313`).
- FluidAudio's `OfflineDiarizerManager` is explicitly designed for full-audio-file post-pass diarization and processes segmentation plus embedding extraction concurrently (`https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift#L98-L123`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift#L139-L180`).

Likely improvement:
- keep a temporary WAV/CAF during capture
- at `endSession()`, run offline diarization reconciliation before final persistence/export
- delete the audio artifact by default after finalization to preserve the product's privacy posture

### 5. `swift-scribe` is useful as a strategy reference, but not as a direct implementation template
- `swift-scribe` uses Apple's `SpeechTranscriber` with `reportingOptions: [.volatileResults]` and `attributeOptions: [.audioTimeRange]`, then maintains separate volatile and finalized transcript buffers (`https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Transcription/Transcription.swift#L54-L59`, `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Transcription/Transcription.swift#L93-L103`).
- That is conceptually relevant: keep volatile text separate from durable text, and carry time ranges on the text stream when the transcription stack supports it.
- But `swift-scribe`'s speaker alignment is intentionally approximate. It proportionally slices the full transcript string across diarization segments and even comments that a production app would want something more sophisticated (`https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L322-L324`, `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L329-L347`).

Takeaway:
- copy the architectural pattern, not the alignment heuristic
- the useful parts are:
  - write temp audio
  - keep live transcript state separate from final transcript state
  - do a post-stop diarization pass

### 6. Interview Partner is pinned to an older FluidAudio revision and misses newer upstream Sortformer options
- The app currently pins FluidAudio to revision `9830ce835881c0d0d40f90aabfaae3a6da5bebfb` (`Packages/InterviewPartnerServices/Package.swift:17`).
- The live diarization engine also hardcodes `SortformerConfig.default` and `SortformerPostProcessingConfig.default` (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:126`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:583`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:584`).
- Upstream FluidAudio `main` was updated on March 19, 2026 and now exposes explicit `fastV2`, `fastV2_1`, `balancedV2`, and `balancedV2_1` Sortformer configs. The balanced variants keep ~1.04s latency but use a larger FIFO for better quality (`https://github.com/FluidInference/FluidAudio/commit/581e215e899ae5474ab5cb97bd82f35a9fd13c49`, `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Sortformer/SortformerTypes.swift#L124-L170`).
- The older docs in the pinned checkout already show that Sortformer quality/latency is highly configuration-dependent and that right context / FIFO behavior matters to real-world diarization (`./.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Documentation/Diarization/Sortformer.md:104`, `./.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Documentation/Diarization/Sortformer.md:120`, `./.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Documentation/Diarization/Sortformer.md:148`).

Likely improvement:
- benchmark a dependency bump plus newer balanced Sortformer configs before doing deeper custom work
- separately tune post-processing thresholds instead of leaving onset/offset/min-duration values at all-zero defaults

### 7. FluidAudio's batch diarization path also supports speaker identity stabilization, which the app does not use yet
- `DiarizerManager` supports `initializeKnownSpeakers(_:)` and `extractSpeakerEmbedding(from:)`, which can anchor diarization to previously known speaker profiles (`./.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift:71`, `./.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift:78`).
- Interview Partner currently maps speakers only to generic labels based on first observed slot order (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:631`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:834`).

Likely improvement:
- if the product really wants `Interviewer` vs `Participant`, add optional interviewer voice enrollment or session-start calibration
- even a lightweight "device owner voice profile" would likely improve role labeling more than trying to infer role purely from slot order

## Code References
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:96` - fixed EOU debounce configuration used for turn finalization.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:327` - turn creation from cumulative transcript delta.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:340` - speaker attribution is requested at turn-finalization time.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:428` - prefix-diff logic that assumes cumulative transcripts never revise earlier text.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:491` - dominant-overlap speaker matcher.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:617` - live diarization attribution uses previous boundary plus EOU debounce.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:583` - live diarization defaults to `SortformerConfig.default` and default post-processing.
- `Packages/InterviewPartnerServices/Package.swift:20` - FluidAudio dependency is pinned to an older revision.
- `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadManager+Streaming.swift#L10-L27` - streaming VAD entry point.
- `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/VAD/VadManager+Streaming.swift#L57-L90` - VAD emits `speechStart` and `speechEnd`.
- `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift#L746-L785` - lower-level streaming ASR exposes token timings and confirmation.
- `https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift#L98-L123` - offline diarizer supports file-based post-pass processing.
- `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Audio/Recorder.swift#L295-L313` - `swift-scribe` runs diarization after stop.
- `https://raw.githubusercontent.com/FluidInference/swift-scribe/main/Scribe/Transcription/Transcription.swift#L93-L103` - `swift-scribe` separates volatile and finalized transcript state.

## Architecture Insights
- The repo currently fuses ASR and diarization too late for accurate live turn boundaries and too early for durable speaker truth.
- Live transcription and live speaker labeling should remain separate concerns:
  - transcription should decide what words belong to the current utterance
  - diarization should decide who spoke those words over a real speech window
- The current code has the right provisional/final model in spirit, but only one diarization pipeline. A stronger product architecture is:
  - streaming ASR for live text
  - streaming VAD for speech boundaries
  - streaming diarization for provisional labels
  - offline diarization for final labels before persistence/export

## Open Questions
- Whether the product is willing to keep temporary session audio until `endSession()` to unlock a stronger offline diarization pass.
- Whether the team wants role labels (`Interviewer`, `Participant`) or only stable speaker separation (`Speaker A`, `Speaker B`) during capture.
- Whether upgrading from pinned FluidAudio revision `9830ce...` to a newer upstream revision introduces any iOS 18 packaging/build regressions.
- Whether it is worth replacing `StreamingEouAsrManager` entirely with `StreamingAsrManager` + VAD, or whether VAD-augmented EOU is good enough for v1.

## Recommended Next Moves
1. Add FluidAudio streaming VAD to the existing audio tap and use `speechStart` / `speechEnd` to define turn windows and gap windows.
2. Keep live labels provisional, but stop estimating turn boundaries from `audioDuration - debounce` alone.
3. Record temporary session audio and run an offline diarization reconciliation pass before `finalizeSession()`, deleting the temp audio afterward by default.
4. Benchmark a FluidAudio dependency bump and newer balanced Sortformer configs on real two-speaker interview audio before larger ASR pipeline changes.
5. If role labels matter, prototype interviewer voice enrollment using FluidAudio speaker embeddings rather than relying on slot order.
