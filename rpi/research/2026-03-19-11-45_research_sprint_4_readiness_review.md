---
date: 2026-03-19T11:45:38-0700
researcher: Jason Wu / Codex
topic: "Sprint 4 readiness review"
tags: [research, sprint-4, ios, polish, readiness]
status: complete
---

# Research: Sprint 4 readiness review

## Research Question
Review Sprint 4 in `rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md`. Are there any ambiguities to clarify before implementation, open questions to answer, or prerequisites to set up?

## Summary
Sprint 4 is mostly implementable, but five items should be clarified first because they change data shape, UX behavior, or release setup:

1. Countdown timer scope is underspecified and currently has no backing model field, so it is not just UI polish (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:348`, `Packages/InterviewPartnerDomain/Sources/InterviewPartnerDomain/SessionModels.swift:153`, `Packages/InterviewPartnerData/Sources/InterviewPartnerData/PersistenceModels.swift:57`).
2. The backgrounding requirement conflicts with current timer semantics: Sprint 4 says the timer pauses/resumes, but the coordinator derives elapsed time from `startedAt`, which will include background time after resume (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:342`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:83`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:206`).
3. Mic-denied and fallback behavior need UX decisions. Mic permission is already requested on session start, but denial only produces a generic error message and no Settings deep link (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:62`). Speech fallback also introduces a second authorization path not mentioned in Sprint 4 (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:241`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:704`).
4. "Cap live view at last 50 turns" needs an explicit rule that this is render-only, not data truncation, otherwise it risks conflicting with the plan’s incremental persistence contract (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:350`, `rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:398`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:496`).
5. TestFlight work has external prerequisites not yet visible in project config: the repo has bundle ID/version config, but no `DEVELOPMENT_TEAM` is set in project settings, so signing/App Store Connect setup is still needed before the release tasks can start (`Config/Shared.xcconfig:11`, `Config/Shared.xcconfig:12`, `Config/Shared.xcconfig:13`, `InterviewPartner.xcodeproj/project.pbxproj:372`).

## Detailed Findings

### Countdown Timer Needs A Product Decision
- Sprint 4 adds "optional countdown — user sets target duration in setup sheet, countdown shown in header" (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:348`).
- The setup flow and current session models do not contain any target-duration field (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:23`, `Packages/InterviewPartnerDomain/Sources/InterviewPartnerDomain/SessionModels.swift:153`, `Packages/InterviewPartnerData/Sources/InterviewPartnerData/PersistenceModels.swift:57`).
- This means implementation requires deciding whether target duration is persisted on `Session`, exported in JSON/Markdown, surfaced in session history, and editable after start.
- The PRD implies setup-time duration is part of pre-interview setup, but still optional (`docs/interview-partner-prd-v2.md:417`, `docs/interview-partner-prd-v2.md:1054`).

### Background Timer Semantics Are Inconsistent
- Sprint 4 says: "audio continues (`UIBackgroundModes: audio`), timer pauses/resumes, UI restores on foreground" (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:342`).
- The current coordinator cancels the timer publisher in background, but recomputes elapsed from `Date.now.timeIntervalSince(startedAt)` on every tick (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:83`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:206`).
- In practice, that means the displayed timer will jump forward and include background time after foregrounding, which is not the same as "pause/resume."
- Clarify whether the timer is supposed to show wall-clock interview duration or only foreground-visible elapsed UI time.

### Permission UX Is Only Partially Specified
- Sprint 4 lists microphone permission work, but the app already requests mic access on first session start (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:62`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/SupportServices.swift:17`).
- The current denied-state UX is only a generic error string: "Microphone access is required..." with no in-context recovery or Settings link (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:72`).
- Sprint 4 should clarify where the denied UI lives: setup sheet inline state, alert, full-screen blocker, or persistent banner.
- It should also specify whether to add a direct Settings deep link and whether the "Start Interview" button remains enabled after denial.

### Speech Fallback Adds A Second Permission Path
- Sprint 4 says FluidAudio fallback should activate silently and continue with `SFSpeechRecognizer` (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:343`).
- The fallback implementation currently requests Speech authorization at runtime before starting (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:241`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:704`).
- That creates an open product question: if FluidAudio fails and Speech permission has not yet been granted, is a second system prompt acceptable in the middle of session start?
- Also clarify the terminal behavior if Speech auth is denied or on-device recognition is unavailable. The current code throws errors in that case (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:705`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:712`).

### Transcript Performance Item Needs Guardrails
- Sprint 4 asks to cap the live transcript to the last 50 turns for performance, while keeping the full transcript in review (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:350`).
- The active session currently renders the entire `transcript` array and auto-scrolls whenever `transcript.count` changes (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:496`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:525`).
- Clarify that the cap is a view-window optimization only. The repo’s reliability contract still requires persisting every turn immediately (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:398`, `Packages/InterviewPartnerData/Sources/InterviewPartnerData/SwiftDataSessionRepository.swift:81`).
- Auto-scroll pause/resume also needs a concrete rule: what counts as "user scrolled up", when the "back to bottom" affordance appears, and whether new turns accumulate unseen while paused.

### Privacy Disclosure Has No Placement Yet
- The PRD requires a first-launch disclosure with exact copy (`docs/interview-partner-prd-v2.md:187`), and Sprint 4 repeats that requirement (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:337`).
- The current root view goes straight into the tab UI with no first-launch gate or persisted acknowledgement state (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/InterviewPartnerRootView.swift:12`).
- Clarify whether this is a blocking modal, dismissible info card, or one-time onboarding screen, and whether it should be reachable later from Settings.

### Accessibility Baseline Is Mostly Execution, Not Discovery
- Some icon-only controls already have 44pt frames and VoiceOver labels (`Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:468`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:720`).
- I did not find explicit Dynamic Type validation or targeted accessibility/UI tests in the repo (`InterviewPartnerUITests/InterviewPartnerUITests.swift:18`).
- This is less a spec ambiguity than a pre-implementation verification gap: define the acceptance pass you want for large content sizes and VoiceOver before coding tweaks piecemeal.

### Release/TestFlight Work Has External Setup Dependencies
- Sprint 4 includes archive/upload and internal TestFlight distribution (`rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:357`).
- The repo already defines bundle ID/version and entitlements path (`Config/Shared.xcconfig:11`, `Config/Shared.xcconfig:12`, `Config/Shared.xcconfig:33`), but the Xcode project does not show a configured `DEVELOPMENT_TEAM` in build settings (`InterviewPartner.xcodeproj/project.pbxproj:372`).
- Before implementation starts, confirm Apple Developer/App Store Connect ownership, signing team selection, and the real bundle identifier you plan to ship.

## Code References
- `rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:336` - Sprint 4 permissions/privacy scope
- `rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:342` - Sprint 4 resilience requirements
- `rpi/plans/2026-03-17-15-52_interview-partner-impl-plan_enhanced.md:347` - Sprint 4 UX hardening items
- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:62` - Existing mic permission request path
- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:83` - Current background/foreground timer handling
- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift:496` - Current transcript rendering behavior
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:241` - Speech fallback start path
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/WorkspaceServices.swift:207` - Export behavior and local fallback
- `Config/InterviewPartner-Info.plist:25` - Existing microphone/speech usage descriptions and background audio mode

## Architecture Insights
- Sprint 4 is not purely "polish." The countdown timer changes domain/persistence/export shape unless you explicitly scope it to transient UI only.
- The strongest hidden risk is permission layering: microphone permission is accounted for, but speech-recognition fallback permission is not surfaced in the plan.
- Several Sprint 4 tasks are verification tasks rather than new engineering work. Mic permission request, background audio plist config, export fallback, and some accessibility work already exist in code and mainly need UX refinement plus test coverage.

## Open Questions
- Should target duration be persisted on `Session`, exported, and shown in review/history, or is it only a transient live-session UI value?
- Should the active-session timer show wall-clock elapsed time or pause while the app is backgrounded/inactive?
- If mic permission is denied, what exact recovery UX do you want: inline explanation, alert, dedicated blocker, and/or Settings deep link?
- Is a second Speech permission prompt acceptable when FluidAudio fallback kicks in, or should Sprint 4 avoid fallback unless Speech auth is already available?
- For the "last 50 turns" cap, is the intended behavior to keep all turns in memory/persistence and only window the rendered list?
- Should the first-launch privacy disclosure require explicit acknowledgement, and should it be visible again in Settings?
- Are you targeting only your own internal device/TestFlight flow, or do you want Sprint 4 to leave the project in a state ready for broader team distribution?
