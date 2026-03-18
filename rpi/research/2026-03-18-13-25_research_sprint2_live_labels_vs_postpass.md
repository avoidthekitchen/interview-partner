---
date: 2026-03-18T13:25:00-07:00
researcher: Jason Wu / Codex
topic: "Sprint 2 live labels vs post-pass diarization alignment"
tags: [research, diarization, transcription, sprint2, fluidaudio, swift-scribe]
status: complete
---

# Research: Sprint 2 live labels vs post-pass diarization alignment

## Research Question
Compare the current Sprint 0.5 spike in Interview Partner against FluidInference's `swift-scribe` example and recommend whether Sprint 2 should keep provisional live speaker labels, copy a post-pass approach, or combine both.

## Summary
Interview Partner's Sprint 0.5 spike currently performs true live labeling by running `StreamingEouAsrManager` and `SortformerDiarizer` in parallel on the same microphone stream, then heuristically assigning each finalized EOU turn to the dominant diarization segment overlap (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:23`, `InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:64`). This gives immediate labels but relies on inferred turn timing because the ASR callback still exposes transcript strings only (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/ContentView.swift:45`).

`swift-scribe` uses a different compromise. It transcribes and diarizes in parallel during capture, but its diarization path buffers audio and runs `DiarizerManager.performCompleteDiarization(...)` on accumulated audio, then aligns speaker segments to transcript text only after recording stops. Its own code labels that alignment as "Simple" and says a production app would want something more sophisticated. See `DiarizationManager.swift:70-94` and `Recorder.swift:295-340` from the upstream repo:
- [DiarizationManager.swift](https://raw.githubusercontent.com/FluidInference/swift-scribe/refs/heads/main/Scribe/Audio/DiarizationManager.swift)
- [Recorder.swift](https://raw.githubusercontent.com/FluidInference/swift-scribe/refs/heads/main/Scribe/Audio/Recorder.swift)

Recommendation: Sprint 2 should keep provisional live labels in-session, but add a post-session reconciliation pass before persistence/export. That preserves the UX benefit you want while reducing the risk that today's heuristic live assignments become the permanent record.

## Detailed Findings

### Interview Partner Spike Design
- The current coordinator starts both streaming ASR and the separate diarization engine before audio capture starts, then feeds both from the same input tap (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:57-84`, `InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:147-159`).
- Live diarization is powered by `SortformerDiarizer`, and the spike stores both finalized and tentative speaker segments over the shared audio timeline (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:171-256`).
- Finalized transcript turns are labeled by `DominantSpeakerMatcher.attributeNextTurn(...)`, which:
  - estimates the turn end as current audio duration minus EOU debounce
  - uses the previous finalized boundary as the turn start
  - assigns the top overlapping speaker unless overlap is weak or ambiguous (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:64-127`).
- The UI already frames these labels as provisional by exposing the EOU-aligned window and confidence rather than pretending the label is native ASR output (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/ContentView.swift:112-180`).

### Why The Current Live Labels Are Still Heuristic
- The ASR callback supplies transcript strings, not native speaker IDs or turn timestamps, so turn timing is inferred from shared audio progress plus debounce (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:121-125`, `InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:72-74`).
- That means ambiguity is structural, not just implementation quality:
  - short backchannels can be swallowed into a neighboring EOU turn
  - overlap can produce competing diarization segments in the same inferred turn window
  - debounce changes shift estimated turn end times and therefore speaker assignment (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:104-116`).
- The current matcher already needs fallbacks for no overlap, weak overlap, and competing overlaps, which is a sign that this is an alignment layer rather than a direct API mapping (`InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:96-158`).

### How `swift-scribe` Handles The Same Problem
- `swift-scribe` records audio once and feeds both transcription and diarization during capture (`Recorder.swift:80-89`).
- Its diarization manager accumulates audio samples and only processes when explicitly asked, with `enableRealTimeProcessing` defaulting to `false` (`DiarizationManager.swift:16-18`, `DiarizationManager.swift:79-94`).
- After stop, it calls `processFinalDiarization()`, stores diarization segments, and only then tries to align transcription text to speakers (`Recorder.swift:127-129`, `Recorder.swift:295-313`).
- The alignment itself is intentionally approximate:
  - it proportionally slices the full transcript string across diarization segments (`Recorder.swift:322-340`)
  - its memo model later estimates character ranges from timing using another rough approximation (`MemoModel.swift:163-196`)
- In other words, `swift-scribe` avoids claiming precise live speaker-to-turn attribution. It prefers a post-pass that can be corrected or visually styled later.

### Sprint 2 Tradeoff
- Keeping only live labels:
  - Pros: good in-session UX, useful for transcript readability while the interview is happening.
  - Cons: the heuristic assignment becomes the canonical stored truth too early.
- Copying `swift-scribe` exactly:
  - Pros: simpler mental model and less in-session mislabeling pressure.
  - Cons: you lose the main UX value you said you prefer, namely live provisional labels.
- Hybrid approach:
  - Keep the current live overlap-based labels for the active session view.
  - Mark them provisional in state and UI.
  - On `endSession()`, run a post-pass reconciliation over the full transcript + full diarization timeline and overwrite stored/exported speaker labels only where confidence improves.
  - If the post-pass remains ambiguous, persist `Unclear` and rely on review editing.

## Code References
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:23` - Streaming ASR is configured separately from diarization.
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:147` - One audio tap feeds both ASR and diarization.
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/TranscriptionSpikeCoordinator.swift:180` - Finalized turns are labeled after EOU using the diarization attribution result.
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:64` - Dominant-overlap speaker matching logic.
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/DiarizationSpikeSupport.swift:171` - Separate live Sortformer diarization engine.
- `InterviewPartnerPackage/Sources/InterviewPartnerFeature/ContentView.swift:129` - UI already exposes confidence and time-window details consistent with provisional labels.
- `https://raw.githubusercontent.com/FluidInference/swift-scribe/refs/heads/main/Scribe/Audio/DiarizationManager.swift#L70-L94` - `swift-scribe` buffers audio and processes diarization in accumulated batches.
- `https://raw.githubusercontent.com/FluidInference/swift-scribe/refs/heads/main/Scribe/Audio/Recorder.swift#L295-L340` - post-stop diarization and simple transcript-to-speaker alignment.
- `https://raw.githubusercontent.com/FluidInference/swift-scribe/refs/heads/main/Scribe/Models/MemoModel.swift#L163-L196` - downstream speaker/text attribution uses estimated character positions based on timing.

## Architecture Insights
- FluidAudio's ASR and diarization are separate subsystems, so apps need an ownership decision about where fusion happens.
- Interview Partner currently fuses at live-turn time.
- `swift-scribe` fuses after recording.
- The strongest product design for Interview Partner is likely dual-phase fusion:
  - live fusion for UX
  - post-pass fusion for durable session data and export

## Open Questions
- Whether `SortformerDiarizer` is reliable enough on real device microphone audio for a full interview-length session with backgrounding enabled.
- Whether Sprint 2 should preserve both `provisionalSpeakerLabel` and `finalSpeakerLabel` in the session model rather than overwriting one field.
- Whether post-pass reconciliation should use Sortformer, offline `DiarizerManager`, or full `OfflineDiarizerManager` once the complete session audio file exists.
