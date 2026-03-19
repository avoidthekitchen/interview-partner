---
date: 2026-03-19T16:08:00-07:00
researcher: Codex
topic: "Audio integration benchmark path and external interview fixture suitability"
tags: [research, codebase, transcription, eval, audio]
status: complete
---

# Research: Audio integration benchmark path and external interview fixture suitability

## Research Question
Can the repo support a real-audio integration benchmark that would catch “only 3 turns / one speaker,” and is the referenced Listen Notes interview a good candidate fixture source?

## Summary
Yes on the benchmark path: the repo now has an audio-driven benchmark runner in [AudioIntegrationBenchmarkRunner.swift](/Users/mistercheese/.codex/worktrees/c385/interview-partner/Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/AudioIntegrationBenchmarkRunner.swift) and a CLI mode in [main.swift](/Users/mistercheese/.codex/worktrees/c385/interview-partner/Packages/InterviewPartnerServices/Sources/InterviewPartnerTranscriptionEvalCLI/main.swift). This runner feeds real audio through the same ASR, VAD, live diarization, and offline reconciliation stack, then scores the resulting turns with the same metric schema as the replay benchmark.

Not yet on checked-in fixtures: the current repo does not contain an aligned real-audio + ground-truth transcript fixture that can be used to validate this mode meaningfully. The new runner is ready, but it needs properly aligned source assets.

The referenced Listen Notes page is technically useful as a candidate because it exposes a timestamped transcript and points to the episode source. But it is not a good checked-in fixture candidate by default because the page itself says the embedded podcast content is from iHeartPodcasts and not Listen Notes, which implies third-party ownership and licensing concerns. The safer use is local/manual benchmarking after the user provides or approves source audio and a short excerpt.

## Detailed Findings

### Audio integration benchmark support now exists
- The new runner reads an actual audio file, streams it through `StreamingEouAsrManager`, `StreamingVadEngine`, `LiveDiarizationEngine`, and `OfflineDiarizationReconciler`, and then emits the same benchmark report shape as replay (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/AudioIntegrationBenchmarkRunner.swift`).
- The eval CLI now supports `--mode audio-integration` so this path is runnable without app UI plumbing (`Packages/InterviewPartnerServices/Sources/InterviewPartnerTranscriptionEvalCLI/main.swift`).
- This path is what can catch “the live session only emitted a few early turns” because it processes real audio instead of replaying synthetic `cumulative_transcript` frames.

### The missing piece is aligned audio fixtures
- Existing replay fixtures are synthetic and mostly short; they are not suitable ground truth for real audio mode.
- The current `two_speaker_pause.wav` resource is only 3.0 seconds long and was not used by the replay runner as audio truth, so it is not enough to validate the new integration mode by itself.
- To make the audio-driven path useful, the repo needs a separate fixture set with:
  - a short excerpted audio file
  - expected turns with start/end times and speaker labels
  - ideally an explicit note on provenance/license

### The Listen Notes episode is better as a local/manual source than a committed repo fixture
- The Listen Notes page shows a transcripted episode published on February 24, 2026, with a 29:07 runtime and a transcript anchor on-page. Source: [Listen Notes episode page](https://www.listennotes.com/podcasts/amy-tj/he-yelled-n-er-at-two-black-KWCuxG6TB7y/).
- The page also says the embedded podcast and artwork are from iHeartPodcasts, which indicates the underlying content is third-party owned rather than provided under a repo-friendly benchmark license. Source: [Listen Notes episode page](https://www.listennotes.com/podcasts/amy-tj/he-yelled-n-er-at-two-black-KWCuxG6TB7y/).
- Because of that, the prudent approach is:
  - use only a short excerpt locally
  - avoid checking third-party audio/transcript into the repo unless the user confirms rights/permission
  - if used at all, prefer a manually prepared fixture file that references a local path outside source control

## Code References
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/AudioIntegrationBenchmarkRunner.swift` - real-audio benchmark runner.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerTranscriptionEvalCLI/main.swift` - CLI support for `--mode audio-integration`.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionEvaluation/TranscriptionBenchmarkRunner.swift` - replay benchmark for comparison.
- `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval/three_speaker_roundtable_long.json` - longer replay fixture that now stresses turn/session/speaker coverage.

## Architecture Insights
The replay benchmark and audio integration benchmark should coexist. Replay is deterministic and fast for validating assembly/reconciliation logic. Audio integration is slower and model-dependent, but it is the only way to catch ingestion backlog, callback starvation, ASR truncation, and speaker collapse in practice.

## Open Questions
- The next useful implementation step is a local-only integration fixture workflow that accepts user-supplied audio and an excerpt transcript without committing the source media to git.
- If the user wants the Listen Notes/iHeart episode in the repo as a benchmark asset, rights and redistribution expectations need to be made explicit first.
