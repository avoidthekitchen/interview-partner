---
date: 2026-03-19T15:23:00-07:00
researcher: Codex
topic: "Live transcription backlog after VAD/offline diarization changes"
tags: [research, codebase, transcription, audio, backlog]
status: complete
---

# Research: Live transcription backlog after VAD/offline diarization changes

## Research Question
Why did a simulator session produce far less transcript than expected after the VAD/offline diarization implementation, and what is the lowest-risk fix?

## Summary
The regression is in the live ingestion path, not in export or offline reconciliation. The audio tap was doing four pieces of work in series per buffer, and ASR ingestion was last in that sequence (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:338-367`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:740-768`). That means ASR callbacks could lag behind real time as VAD, diarization, and audio-file writes accumulated ahead of it. On stop, the service previously removed the tap and immediately finalized ASR without waiting for already-enqueued tap work to finish (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:151-205`). Those two facts together explain a long recording exporting only an early prefix of the session.

The fix is to prioritize ASR ingestion first for each buffered chunk and to drain all in-flight tap work before calling `finish()` on the ASR stream (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:151-205`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:740-832`). Additional structured logs now record callback counts, turn finalization windows, and pending-buffer backlog so the next simulator run will show whether the live path is keeping up (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:378-460`).

## Detailed Findings

### Live audio ingestion had ASR at the back of the queue
- The tap startup wires ASR, diarization, VAD, and session audio capture into a single callback path (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:338-367`).
- Before the fix, the tap task awaited audio capture, diarization, and VAD before it ever called `asrManager.process(...)`; after the fix, ASR is now first (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:740-768`).
- This matters because ASR partials and EOU finalizations drive the user-visible transcript (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:304-318`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:378-460`).

### Stop previously finalized without draining enqueued tap work
- `stop()` tears down the audio engine and then finalizes the ASR stream (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:151-205`).
- Without a drain step, any chunks already copied out of the tap but not yet ingested by ASR are effectively invisible to `finish()`.
- The new `AudioTapWorkTracker` gives the service a concrete “pending buffers” count and an `await` point before finalization (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:786-832`).

### The existing turn assembly path was not the main truncation culprit
- Partial and EOU callbacks remain the only way turns are appended (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:304-318`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:389-460`).
- VAD only shapes the timing window after an EOU arrives; it does not suppress ASR output on its own (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:406-440`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/VadBoundaryTracker.swift:31-75`).
- That makes a backlog before ASR ingestion a better fit than “VAD misclassified speech” for a session that stopped producing transcript almost entirely.

## Code References
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:151-205` - `stop()` now logs backlog state, waits for idle, then finalizes ASR.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:338-367` - audio engine setup for the live tap path.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:378-460` - partial/EOU handling and new instrumentation for callback counts and finalized windows.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:740-832` - reordered tap processing and the new `AudioTapWorkTracker`.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/Transcription/VadBoundaryTracker.swift:31-75` - VAD windows affect timing attribution, not whether ASR emits text.
- `Packages/InterviewPartnerServices/Tests/InterviewPartnerServicesTests/AudioTapWorkTrackerTests.swift:5-21` - regression test covering “wait until backlog drains.”

## Architecture Insights
The new VAD/offline diarization work increased the amount of per-buffer side work, but the service architecture still treated all of it as equally urgent inside the tap task. In practice, ASR ingestion is latency-critical while audio capture, diarization, and VAD can trail slightly behind without hurting the visible transcript. The service also needed an explicit lifecycle boundary between “no new buffers are entering” and “all previously enqueued buffers are fully processed.”

## Open Questions
- The next simulator rerun should confirm whether callback counts and pending-buffer counts stay close to real time under actual speech. If pending buffers spike during a normal session, the live path may still need deeper pipelining.
- The current fix improves throughput and stop correctness, but it does not independently prove that live speaker attribution quality is materially better. That still needs a fresh user run with the new logs.
