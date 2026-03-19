---
date: 2026-03-19T15:34:00-07:00
researcher: Codex
topic: "Current transcription eval scope and gaps"
tags: [research, codebase, transcription, eval]
status: complete
---

# Research: Current transcription eval scope and gaps

## Research Question
Does the current automated eval measure EOU turn finalization and speaker diarization quality well enough to catch the live regression seen in manual testing, and how should it be improved?

## Summary
The current benchmark does measure some EOU and diarization quality, but only in a narrow replay harness. It scores turn-boundary timing, finalization delay, split/merge mismatches, live/final speaker accuracy, unclear rate, offline runtime cost, and missing VAD speech-end events (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:67-130`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:363-392`).

It does not run real audio through the live service. Instead, it replays synthetic frames that already contain cumulative transcript text, diarization segments, VAD events, and EOU flags (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/TurnAttributionModels.swift:105-133`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:276-333`). That means it cannot catch the failure mode you saw, where live transcription appears to stall and only a small prefix of the session is emitted.

The current fixtures are also too small: three fixtures, each with only two expected turns (`Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/baseline_short_ack.json:1`, `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/overlap_repair.json:1`, `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/revision_long_pause.json:1`). A system that only produces two or three turns can still look acceptable if those first few turns align with the fixture.

## Detailed Findings

### What the benchmark currently measures
- `turn_boundary_mae_ms` compares predicted vs expected start/end boundaries (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:4-16`).
- `late_finalization_p95_ms` measures how long after the expected end a turn finalized (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:18-29`).
- `split_merge_error_count` penalizes count mismatches and text mismatches (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:31-42`).
- `live_speaker_accuracy`, `final_speaker_accuracy`, and `unclear_rate` measure speaker labeling on paired turns (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/SpeakerMetrics.swift:4-27`).
- The tests explicitly assert boundary/finalization/split-merge improvements and speaker non-regression (`Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/TranscriptionEvaluationTests.swift:5-30`, `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/TranscriptionEvaluationTests.swift:33-58`).

### Why it misses the manual regression
- The harness never runs ASR, VAD, or diarization models against audio. It consumes fixture-provided `cumulative_transcript`, `vad_event`, and `diarization_segments` fields directly (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:276-333`).
- `audio_file_name` exists in the fixture schema, but the runner never reads or uses that audio file (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:25-64`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:225-258`).
- Because of that, live-path issues like ingestion backlog, callback starvation, truncated sessions, or model/runtime interactions are completely outside the benchmark’s coverage.

### The scoring underweights missing-turn failures
- Boundary and speaker metrics use `zip(actual, expected)`, so they only score the overlapping prefix of turns (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:8-15`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:22-24`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/SpeakerMetrics.swift:9-18`).
- If a long fixture expected 10 turns and the system emitted only 3, those metrics would only score the first 3 pairs. The missing 7 turns would mainly show up indirectly through `split_merge_error_count`, not as direct recall loss.
- The current fixtures all expect exactly 2 turns, which makes this weakness harder to notice.

### The fixtures are too small and too idealized
- All three baseline fixtures are short synthetic two-turn cases (`Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/baseline_short_ack.json:1`, `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/overlap_repair.json:1`, `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/revision_long_pause.json:1`).
- They are good for unit-level validation of VAD windowing and offline speaker reconciliation, but not for end-to-end session health or speaker-cardinality quality.
- The offline reconciliation path is also fed fixture-provided final diarization segments rather than measured model output, so “final speaker accuracy” here is mostly checking the reconciliation logic, not the full offline diarization system.

## Code References
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:67-130` - benchmark metric definitions.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:276-333` - replay loop driven by synthetic frame fields.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift:335-392` - final metric computation.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/BoundaryMetrics.swift:4-42` - boundary and split/merge scoring.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/SpeakerMetrics.swift:4-27` - speaker accuracy and unclear-rate scoring.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/TurnAttributionModels.swift:105-133` - replay-frame schema.
- `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/TranscriptionEvaluationTests.swift:5-58` - current eval assertions.

## Architecture Insights
The current benchmark is best understood as a deterministic logic replay test for turn assembly and reconciliation. It is fast and useful, but it is not an end-to-end transcription benchmark. It validates policy decisions after transcripts, VAD boundaries, and diarization segments already exist.

## Open Questions
- The repo still needs a slower integration benchmark that feeds real audio through the actual service or a close equivalent.
- The benchmark should add direct recall/coverage metrics so “produced only a few turns” fails loudly instead of hiding behind prefix-based zips.
