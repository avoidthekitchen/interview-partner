# Interview Partner — Implementation Plan
**v1.1 · March 2026 · Jason Wu**

> **Build context:** Solo · iOS-native SwiftUI · Target: 2–4 weeks to first real interview · Scope: Phase 1 only, no AI features
>
> **v1.1 changes:** Adopted Codex package architecture; added repository protocol layer; incremental session persistence; security-scoped bookmark handling; export retry queue; `TranscriptGap` modeling; forward-compatibility stubs in guide JSON; corrected export paths. Dropped blank session from v1 scope.

---

## 01 — Resolved Technical Decisions

All architectural choices locked before sprint work begins.

| Decision | Choice | Rationale |
|---|---|---|
| Data framework | SwiftData | iOS 17+ minimum target; dramatically less boilerplate than CoreData for vibe-coding. `@Model` annotations, no XML schemas. |
| State management | `@Observable` (iOS 17) | Simpler than `ObservableObject`/`@StateObject`. Cleaner code generation with Claude. No going back after Sprint 0. |
| FluidAudio API path | `StreamingEouAsrManager` | EOU detection gives natural utterance boundaries. `setPartialCallback` for in-progress text, `setEouCallback` for finalized `TranscriptTurn` appends. No manual segmentation needed. |
| Speaker labels (live) | Speaker A / Speaker B | Neutral, stable labels during session. User renames post-session in transcript editor before export. |
| Mid-session correction | Not built (v1) | Post-session label editing is the escape valve. Diarization errors flagged as `[unclear]`, not confidently mislabeled. |
| iCloud setup | Hard gate at onboarding | Required before first session. If iCloud Drive is disabled on device, fall back to local-only export with a persistent warning banner. |
| Session setup flow | Sheet on `SessionListView` | Guide selection required. Participant label optional. No target duration required to start — timer shown, countdown optional. |
| Blank session path | **Deferred to v2** | Not needed for your own use case. Team-rollout scenario (the motivating use case) is Phase 2. |
| Workspace folder access | Security-scoped bookmark | Persist bookmark in `UserDefaults` after folder pick so access survives app restarts without re-prompting. Fallback to app documents directory if iCloud Drive unavailable. |
| Runtime source of truth | SwiftData (local) | SwiftData is canonical at runtime. Workspace files are export artifacts, not the live datastore. Never read from workspace files to populate UI. |
| Export retry | Lightweight queue | Pending session IDs stored locally; retried on app foreground and workspace reconnect. No retry UI in v1 — silent background behavior only. |
| Export paths | Session-ID-based folders | `InterviewPartner/guides/[guide-slug].json` and `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/`. Participant label in file headers only, not in folder names (avoids collisions). |

---

## 02 — Data Model

Seven SwiftData entities. Define all of them in Sprint 1 before building any views. The relationships are where bugs hide; review carefully before building on top.

| Entity | Key fields | Notes |
|---|---|---|
| `Guide` | `id, name, goal, createdAt`<br>`questions: [Question]` | Reusable template. Written to `InterviewPartner/guides/[guide-slug].json` on save. JSON includes `branch: null` and `ai_scoring_prompt_override: null` stubs for forward compatibility — Phase 2 will populate these without breaking existing files. |
| `Question` | `id, text, priority`<br>`orderIndex, subPrompts: [String]` | `priority` enum: `mustCover / shouldCover / niceTo Have`. `orderIndex` enables reordering without re-sorting by date. |
| `Session` | `id, guideSnapshot, participantLabel`<br>`startedAt, endedAt` | `guideSnapshot` stores a Codable copy of the guide at session-start — decoupled from live guide edits. |
| `TranscriptTurn` | `id, speakerLabel (A/B)`<br>`text, timestamp, isFinal` | `isFinal` distinguishes partial (in-progress) turns from finalized EOU turns. Only finals are persisted. |
| `TranscriptGap` | `id, sessionId, startTimestamp`<br>`endTimestamp, reason` | Explicit marker for interrupted transcription spans. Rendered visibly in transcript view and exported as `[transcription unavailable HH:MM–HH:MM]`. Better than a silent hole. |
| `QuestionStatus` | `questionId, status`<br>`aiScore (optional)` | `status` enum: `notStarted / partial / answered / skipped`. One record per question per session. `aiScore` always `null` in v1. |
| `AdHocNote` | `id, text, timestamp` | Not tied to any question. Exported in dedicated section of `summary.md`. |
| `ExportQueueEntry` | `id, sessionId, queuedAt`<br>`attemptCount, lastAttemptAt` | Pending export retry queue. Created at session end; deleted on successful write to workspace. Retried on app foreground and workspace reconnect. |

> **⚠️ Critical:** Store a `guideSnapshot` (Codable struct copy) on the `Session` at session-start — not a live reference to the `Guide` entity. If the guide is edited between sessions, old sessions must still reflect the questions that were actually asked.

---

## 03 — Architecture

### Architectural Principle: Local Data Is Always Canonical

SwiftData is the single source of truth at runtime. Workspace files (iCloud folder exports) are write-only artifacts in v1 — they are never read back to populate UI or hydrate state. Guide import from workspace is a deliberate, explicit action (upsert scan on app foreground), not a sync layer. This principle prevents an entire class of conflicts and race conditions.

### Package Structure

Create an Xcode workspace with one iOS app target and four local Swift packages. This separation enforces layering — feature code cannot accidentally reach into persistence, and the data layer can be swapped in a future phase without touching views.

```
InterviewPartner/          ← iOS app target (SwiftUI views, app entry point)
Packages/
  InterviewPartnerDomain/  ← Pure Swift types: domain models, enums, protocols
  InterviewPartnerData/    ← SwiftData schema, repository implementations
  InterviewPartnerServices/← TranscriptionService, WorkspaceExporter, PermissionManager
  InterviewPartnerFeatures/← @Observable feature coordinators (session, guide, review)
```

**Dependency rule:** `App → Features → Services → Data → Domain`. No layer may import above itself. FluidAudio types are confined to `InterviewPartnerServices` and never leak into `Features` or the app target.

### Repository Protocol Layer

Feature coordinators never call SwiftData directly. All persistence goes through protocol-based repositories defined in `InterviewPartnerDomain` and implemented in `InterviewPartnerData`. This makes unit testing straightforward (swap in a mock) and keeps the data layer swappable.

Key protocols:
- `GuideRepository` — CRUD for guides and questions; triggers workspace export on save
- `SessionRepository` — create, incrementally update, and query sessions; creates `ExportQueueEntry` at session end
- `WorkspaceExporter` — writes `transcript.md` and `session.json` to workspace; drains export queue on foreground/reconnect
- `WorkspaceGuideImporter` — upsert scan of `InterviewPartner/guides/` on app foreground and manual refresh
- `PermissionManager` — microphone permission state
- `KeychainStore` — reserved for Phase 2 API key storage; stub in v1

### View Layer — Four Top-Level Screens

| Screen | Responsibility |
|---|---|
| `SessionListView` | Home screen. List of past sessions, "New Session" sheet trigger. |
| `GuideListView` / `GuideEditorView` | Guide CRUD. Accessible from session setup sheet or Settings tab. Guide editor owns question reordering, priority picker, sub-prompts. |
| `ActiveSessionView` | Full-screen modal. Owns transcript display, script panel, session controls. Single `SessionCoordinator` (`@Observable`, in `InterviewPartnerFeatures`) owns all state. Three sub-views: `TranscriptView` (~62% height), `ScriptPanelView` (bottom sheet with three snap states: collapsed / default / expanded), `SessionHeaderView` (timer + end button). |
| `SessionReviewView` | Post-session. Transcript editing, coverage map, ad hoc notes, export. Read-only except for transcript text and speaker label edits. Driven by `ReviewCoordinator`. |

### SessionCoordinator — Central Session State Owner

Lives in `InterviewPartnerFeatures`. `ActiveSessionView` wires to a single `@MainActor @Observable SessionCoordinator`. Do not split into multiple coordinators in v1. Owns:

- `TranscriptionService` reference (injected from `InterviewPartnerServices`)
- `transcript: [TranscriptTurn]` — appended on each EOU callback; persisted incrementally via `SessionRepository`
- `gaps: [TranscriptGap]` — appended when transcription is interrupted; persisted immediately
- `partialTurn: String?` — updated on each partial callback, shown in-progress at bottom of transcript view; never persisted
- `questionStatuses: [QuestionStatus]` — mutated on user tap / long-press; persisted on each change
- `adHocNotes: [AdHocNote]` — appended from quick-capture overlay; persisted immediately
- `elapsedSeconds: Int` — driven by `Timer.publish`
- `endSession()` — stops transcription, finalizes `Session` in SwiftData, enqueues `ExportQueueEntry`

> **Incremental persistence:** Every transcript turn, gap, status change, and note is written through `SessionRepository` immediately — not batched at session end. If the app crashes mid-interview, nothing is lost except the current partial turn.

### TranscriptionService — FluidAudio Isolation Layer

Lives in `InterviewPartnerServices`. `SessionCoordinator` holds one reference. FluidAudio types must not appear outside this package.

Key responsibilities:
- Initialize `StreamingEouAsrManager`
- Configure `AVAudioSession` (`.record`, `.allowBluetooth`) and `AVAudioEngine`
- `setPartialCallback` → publish `partialText: String` to coordinator
- `setEouCallback` → publish finalized `TranscriptTurn` (speaker diarization ID mapped to "Speaker A" / "Speaker B") and detect gaps (interruptions between EOU events > threshold → emit `TranscriptGap`)
- `start()` / `stop()` methods
- Fallback: if FluidAudio fails to init, activate `SFSpeechRecognizer` (on-device flag), set `diarizationAvailable = false`, surface "Limited transcription mode" banner

### Export Layer

Lives in `InterviewPartnerServices` as `WorkspaceExporter`. Two outputs per session:
- `generateTranscriptMarkdown(session:) -> String` — header with participant label + date, turns as `[HH:MM] Speaker A: text`, gap markers as `[transcription unavailable HH:MM–HH:MM]`, ad hoc notes section, coverage summary
- `generateSessionJSON(session:) -> Data` — full session as Codable JSON

**Write strategy:**
1. At session end, `SessionRepository` creates an `ExportQueueEntry` and immediately attempts export
2. On success: delete `ExportQueueEntry`, write files to `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/`
3. On failure (workspace unavailable): leave `ExportQueueEntry` in SwiftData; retry on next app foreground and workspace reconnect
4. Always also write to `NSTemporaryDirectory()` so share sheet works regardless of workspace state

**Workspace access:** Folder URL stored as a security-scoped bookmark in `UserDefaults`. Call `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around all workspace writes. If bookmark resolution fails, fall back to app documents directory and show persistent warning banner.

---

## 04 — Risk Register

Ordered by "what blocks everything else."

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| FluidAudio ↔ SwiftUI wiring harder than expected | Medium | **Blocks Sprint 2** | Spike in isolation (Sprint 0) before building any UI. Exit criterion: two speakers, labeled turns, on screen. |
| `AVAudioSession` background mode silent failure | Medium | **Silent fail in real session** | Test with screen locked before Sprint 2 ends. Verify `UIBackgroundModes: audio` in `Info.plist` directly, not just Xcode Capabilities UI. |
| SwiftData `@Observable` data bugs | Medium | Slows all sprints | Generate model layer with Claude, review relationships carefully before building views on top. |
| iCloud hard gate blocks first real session | Low | Kills 2–4 week target | Fallback to local-only with warning if iCloud Drive disabled. Never block session start on iCloud. |
| Diarization quality worse in real conditions | Medium | Trust/UX issue | Accept in v1. Post-session label editing is the escape valve. `[unclear]` label for ambiguous turns. |
| `guideSnapshot` / live guide divergence | Low | Silent data bug | Snapshot at session-start, not a live reference. Test: edit guide during session, verify old session unchanged. |
| Security-scoped bookmark revoked mid-export | Low | Silent export failure | `ExportQueueEntry` survives; export retried on next foreground. User sees warning banner, not a crash. |
| Package scaffolding overhead delays Sprint 1 | Low | Loses 1–2 days | Use Claude to generate all four `Package.swift` files at once. Review dependency graph before writing any source. |

---

## 05 — Sprint Plan

> **Timeline assumption:** ~2–3 hours of focused building per day. Sprint 0 is not optional — it de-risks the entire plan. If Sprint 0 takes more than 2 days, revise the overall timeline before proceeding.

---

### Sprint 0 — Environment & Spike
**Days 1–2 · Goal: Prove the hardest thing works before touching the real architecture**

This is the only sprint where you build something you'll throw away. The deliverable is confidence, not code. **Do not create the four-package structure yet** — that comes in Sprint 1. A premature scaffold with an unvalidated audio pipeline is wasted scaffolding.

- [x] Xcode project: single SwiftUI app target, iOS 17 minimum, SwiftData enabled
- [x] Add FluidAudio as Swift Package dependency
- [x] Single throwaway view: tap → mic starts → FluidAudio transcribes → text appears on screen
- [x] Wire `setPartialCallback`: in-progress text updates a `@State` string
- [x] Wire `setEouCallback`: finalized turns append to a `[TranscriptTurn]` array
- [x] Verify diarization output: does EOU result carry a speaker ID? What's the type?
- [x] Confirm `AVAudioSession` background mode: lock screen mid-transcription, audio continues
- [x] Verify `UIBackgroundModes: audio` in `Info.plist` file directly (not just Capabilities UI)
- [x] Decision confirmed: `@Observable` + SwiftData — no going back

> **Sprint 0 note:** Current `FluidAudio` `StreamingEouAsrManager` callbacks expose transcript strings only; they do not expose speaker IDs. Sprint 0 therefore proves live transcription only. Labeled speaker turns move to Sprint 0.5.

> **Verification note:** `xcodebuildmcp` simulator build and build-and-run succeed on the installed iPhone 17 simulator runtime. Package compilation and `Info.plist` validation are complete. Manual simulator verification on March 18, 2026 confirmed transcription can continue while the screen is locked mid-session. EOU finalization remains rough and should be refined in later sprint work.

> **Exit criterion:** Tap a button. Speak and see live partial text plus finalized transcript turns on screen. Nothing else. If this takes >2 days, revise your timeline before Sprint 1.

### Sprint 0.5 — Diarization Spike
**Goal: Prototype separate diarization integration for labeled turns before Sprint 2 hardens the session pipeline**

- [x] Evaluate separate live diarization path with `LSEENDDiarizer` or `SortformerDiarizer`
- [x] Determine how diarization timestamps align with `StreamingEouAsrManager` finalized transcript strings
- [x] Prototype a temporary mapping from diarization segments to transcript turns for `Speaker A / Speaker B`
- [x] Re-test background performance with both ASR and diarization active
- [x] Decide whether labeled live turns are viable for Sprint 2 or should fall back to unlabeled/edited-later transcript in v1

> **Sprint 0.5 note:** The current `FluidAudio` checkout exposes `SortformerDiarizer`, `DiarizerManager`, and `OfflineDiarizerManager`; there is no public `LSEENDDiarizer` type in this dependency version. The spike therefore uses `SortformerDiarizer` on the shared microphone stream.

> **Alignment note:** `StreamingEouAsrManager` still emits transcript strings only. The spike estimates each finalized turn's end timestamp from the shared audio timeline using the EOU debounce window, then assigns `Speaker A / Speaker B` from the dominant diarization overlap between sequential turn boundaries. This is technically workable, but it is still a heuristic layer rather than native ASR speaker labeling.

> **Recommendation note (March 18, 2026):** Labeled live turns look technically viable for Sprint 2 only if they remain behind this explicit timestamp-mapping layer and keep an unlabeled fallback. The spike also reduces `StreamingEouAsrManager` EOU debounce from 1280 ms to 640 ms to shorten the long pause observed in Sprint 0. Manual locked-screen/background re-testing with ASR + diarization together is now confirmed, but EOU finalization quality and speaker attribution quality are still only prototype-grade.

> **Verification note:** `xcodebuildmcp swift-package test --package-path /Users/mistercheese/Code/interview-partner/InterviewPartnerPackage`, `xcodebuildmcp simulator build --workspace-path /Users/mistercheese/Code/interview-partner/InterviewPartner.xcworkspace --scheme InterviewPartner --simulator-name "iPhone 17"`, and `xcodebuildmcp simulator build-and-run --workspace-path /Users/mistercheese/Code/interview-partner/InterviewPartner.xcworkspace --scheme InterviewPartner --simulator-name "iPhone 17"` all succeeded on March 18, 2026. Manual device/simulator validation on March 18, 2026 also confirmed ASR plus diarization continue working with the screen locked/backgrounded. Turn finalization and speaker diarization detection are not great yet, but they are good enough for a prototype spike.

> **Exit criterion:** Clear recommendation, backed by a working spike or explicit failure notes, for how Sprint 2 should handle live speaker labeling.

---

### Sprint 1 — Package Scaffold + Data Model + Guide CRUD
**Days 3–6 · Goal: Persistent guides with questions you can create and reuse, on the real architecture**

Sprint 0 proved the audio pipeline works. Now build the structure everything else will live in. Define the full data model — all eight entities — before building any views.

**Package scaffolding**
- [ ] Convert Sprint 0 project to workspace; add four local packages: `InterviewPartnerDomain`, `InterviewPartnerData`, `InterviewPartnerServices`, `InterviewPartnerFeatures`
- [ ] Wire package dependencies: `App → Features → Services → Data → Domain`; verify build succeeds with empty packages before writing source
- [ ] Move `TranscriptTurn` stub type from Sprint 0 spike into `InterviewPartnerDomain` as the canonical domain model
- [ ] Define all service protocols in `InterviewPartnerDomain`: `GuideRepository`, `SessionRepository`, `WorkspaceExporter`, `WorkspaceGuideImporter`, `PermissionManager`, `KeychainStore` (stub)

**Data model** (in `InterviewPartnerData`)
- [ ] Define all SwiftData `@Model` classes: `Guide`, `Question`, `Session`, `TranscriptTurn`, `TranscriptGap`, `QuestionStatus`, `AdHocNote`, `ExportQueueEntry`
- [ ] Define `priority` enum (`mustCover / shouldCover / niceTo Have`) and `status` enum (`notStarted / partial / answered / skipped`)
- [ ] Verify relationships: `Guide` ↔ `Question` (ordered array), `Session` ↔ `QuestionStatus`, `Session` ↔ `TranscriptTurn`, `Session` ↔ `TranscriptGap`, `Session` ↔ `AdHocNote`
- [ ] `guideSnapshot` on `Session`: stored as a Codable struct copy, not a `Guide` reference
- [ ] Implement `GuideRepository` and `SessionRepository` concrete types backed by SwiftData

**Navigation shell** (in app target)
- [ ] Tab bar: Sessions / Guides / Settings
- [ ] `SessionListView`: empty state, list of past sessions (stubbed), "New Session" button (sheet — wired in Sprint 2)

**Workspace setup**
- [ ] Settings tab: iCloud folder picker (`UIDocumentPickerViewController`); persist selection as security-scoped bookmark in `UserDefaults`
- [ ] Onboarding gate: if no bookmark on first "New Session" tap and iCloud Drive available, show setup sheet; if iCloud Drive unavailable, proceed with app documents directory and show warning banner
- [ ] `WorkspaceExporter` stub: resolves bookmark, calls `startAccessingSecurityScopedResource()`, writes files, calls `stopAccessingSecurityScopedResource()`; on bookmark failure, writes to app documents directory

**Guide CRUD**
- [ ] `GuideListView`: list of guides from `GuideRepository`, swipe-to-delete, "New Guide" button
- [ ] `GuideEditorView`: name field, goal/context text area, question list; driven by `@Observable GuideEditorCoordinator` in `InterviewPartnerFeatures`
- [ ] Question row: text field, priority picker (Must Cover / Should Cover / Nice to Have), reorder handle
- [ ] Sub-prompts per question: expandable list, collapsed by default
- [ ] Duplicate guide action (long-press or context menu)
- [ ] On save: write guide JSON to `InterviewPartner/guides/[guide-slug].json` via `WorkspaceExporter`; JSON includes `branch: null` and `ai_scoring_prompt_override: null` stubs

> **Exit criterion:** Create a guide with 5 questions at mixed priorities. Reopen it. Edit a question text. Change a priority. Add a sub-prompt. Delete a question. Duplicate the guide. All changes persist across app restart. Guide JSON appears in the workspace folder with `branch: null` present in the file.

---

### Sprint 2 — Active Session Core
**Days 7–13 · Goal: Run a real (if rough) interview session end-to-end**

> **⚠️ Longest sprint, highest risk.** Budget extra time. The FluidAudio ↔ SwiftUI wiring and the `ScriptPanelView` state interactions are the two hardest pieces in the entire v1 build.

**Session setup sheet**
- [ ] Sheet over `SessionListView`: guide picker (list of guides), optional participant label text field
- [ ] "Start Interview" button → creates `Session` via `SessionRepository`, snapshots guide, presents `ActiveSessionView` as full-screen modal

**TranscriptionService** (in `InterviewPartnerServices`)
- [ ] Move FluidAudio integration from Sprint 0 spike into `TranscriptionService` — this is the permanent home
- [ ] `AVAudioEngine` + `AVAudioSession` setup (`.record`, `.allowBluetooth`)
- [ ] `setPartialCallback` → publishes `partialText: String` to `SessionCoordinator`
- [ ] `setEouCallback` → publishes finalized `TranscriptTurn` text plus inferred turn timing metadata; do **not** assume native speaker IDs exist on the ASR callback
- [ ] Run a separate diarization path alongside streaming ASR (current spike direction: `SortformerDiarizer`) and expose provisional speaker labels plus the underlying speaker timeline to `SessionCoordinator`
- [ ] Gap detection: if gap between EOU events exceeds threshold (e.g. 10s with no audio), emit `TranscriptGap` with start/end timestamps
- [ ] `start()` / `stop()` methods
- [ ] Fallback: if init fails, activate `SFSpeechRecognizer` (on-device), set `diarizationAvailable = false`

**SessionCoordinator (`@MainActor @Observable`, in `InterviewPartnerFeatures`)**
- [ ] Owns `TranscriptionService`, transcript array, gaps array, `partialTurn`, `questionStatuses`, `adHocNotes`, `elapsedSeconds`
- [ ] **Incremental persistence:** each `TranscriptTurn`, `TranscriptGap`, `QuestionStatus` change, and `AdHocNote` written immediately via `SessionRepository` — not batched at session end
- [ ] `Timer.publish` for elapsed time (pauses on app background)
- [ ] Persist live speaker labels as **provisional** during the active session; ambiguous turns remain `Unclear` instead of forcing a confident label
- [ ] `endSession()`: stops transcription, finalizes the full diarization timeline, runs a post-pass reconciliation over transcript turns before export/persistence becomes durable, finalizes `Session` via `SessionRepository`, creates `ExportQueueEntry`, triggers immediate export attempt

**ActiveSessionView layout**
- [ ] `SessionHeaderView`: participant label, elapsed timer, "End" button with confirmation dialog
- [ ] `TranscriptView`: scrolling list of `TranscriptTurn`s and `TranscriptGap` markers, auto-scrolls to latest, Speaker A left-aligned / Speaker B right-aligned, color-coded, partial turn shown in-progress at bottom; gap markers rendered as `[transcription unavailable HH:MM–HH:MM]` in muted style
- [ ] Live speaker chips/labels visually communicate that in-session attribution is provisional (for example, subdued styling, confidence hint, or explicit "live" treatment)
- [ ] "Limited transcription mode" banner if `diarizationAvailable = false`

> **Sprint 2 diarization direction:** Keep live labels because they materially improve in-session readability, but treat them as provisional. The durable session record should come from a post-session reconciliation pass over the completed diarization timeline, not from the first live overlap guess alone.

**ScriptPanelView (bottom sheet)**
- [ ] Collapsible bottom sheet with three snap states: collapsed / default / expanded
- [ ] Header shows "3 of 4 Must Cover · Xm left"
- [ ] Questions grouped by priority (Must Cover → Should Cover → Nice to Have), each with status badge
- [ ] Tap cycles: Not Started → Partial → Answered; each tap persists immediately via `SessionRepository`
- [ ] Long-press marks Skipped, with undo toast (3 seconds)
- [ ] Answered questions dim and float to bottom of group; Skipped show muted strikethrough
- [ ] Ad hoc note button (`+`): one-line overlay with timestamp, saves `AdHocNote` via `SessionRepository` without navigating away
- [ ] Panic button (`⊞`): full-screen question list with all status badges

> **Exit criterion:** Start a session with a guide. Speak for 5 minutes. Manually mark 2 questions Answered, 1 Partial, 1 Skipped. Add one ad hoc note. End the session. Find it in session history. Live labels can still be wrong during capture, but the session must complete with readable provisional attribution and a post-stop reconciliation pass.

---

### Sprint 3 — Session Review + Export
**Days 14–19 · Goal: Produce a shareable artifact from a completed session**

**SessionReviewView** (driven by `@Observable ReviewCoordinator`)
- [ ] Three-tab or segmented view: Transcript / Coverage / Export
- [ ] Transcript tab: editable turns (tap text to edit via `ReviewCoordinator`, committed back to `SessionRepository`); tap speaker label to rename (renames all turns with that label in this session); gap markers shown read-only
- [ ] Review UI loads reconciled speaker labels as the default/session-truth transcript; provisional live attribution is optional diagnostic metadata, not the primary editing surface
- [ ] Coverage tab: read-only question list with final statuses, grouped by priority; ad hoc notes section below
- [ ] Export tab: preview of `transcript.md` content, share sheet trigger

**Export** (in `WorkspaceExporter`)
- [ ] `generateTranscriptMarkdown(session:)`: header with participant label + date, turns as `[HH:MM] Speaker A: text`, gap markers as `[transcription unavailable HH:MM–HH:MM]`, ad hoc notes section, coverage summary
- [ ] Export uses reconciled/final speaker labels rather than raw provisional live labels; ambiguous reconciliations remain visibly `Unclear`
- [ ] `generateSessionJSON(session:)`: full session as Codable JSON with `branch: null` and `ai_scoring_prompt_override: null` stubs
- [ ] Session JSON clearly distinguishes durable/reconciled speaker labels from any optional provisional attribution metadata if both are retained
- [ ] Always write to `NSTemporaryDirectory()` at session end (share sheet source)
- [ ] Write to `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/` via security-scoped bookmark; on success delete `ExportQueueEntry`
- [ ] On workspace failure: leave `ExportQueueEntry` in SwiftData; retry on app foreground and workspace reconnect
- [ ] Share sheet: standard `UIActivityViewController` with `.md` and `.json`

**Export queue drain**
- [ ] On app foreground (`scenePhase == .active`): scan for pending `ExportQueueEntry` records, attempt workspace write for each
- [ ] On bookmark resolution failure: show persistent warning banner in `SessionListView` listing count of pending exports

**Session history**
- [ ] `SessionListView` populated from `SessionRepository` query, sorted by `startedAt` descending
- [ ] Session row: participant label, guide name, date, duration, Must Cover coverage count; pending-export badge if `ExportQueueEntry` exists for session
- [ ] Tap → `SessionReviewView`

> **Exit criterion:** End a session. Open the review. Fix one speaker label — verify all turns for that speaker update. Export to Markdown. Confirm gap markers appear correctly if transcription was interrupted. Share to Files or Notes. Kill the app before the export completes; relaunch; confirm the pending-export badge appears and the export retries successfully.

> **Sprint 3 diarization direction:** Review and export should assume the post-session reconciled transcript is the source of truth. Provisional live labels are useful during capture, but they should not leak into shared artifacts unless explicitly preserved as diagnostic metadata.

---

### Sprint 4 — Polish for First Real Use
**Days 20–25 · Goal: Smooth enough to use in a real interview without embarrassment**

**Permissions & privacy**
- [ ] Microphone permission: request on first session start, graceful error state if denied (explain in UI, link to Settings)
- [ ] Privacy disclosure screen at first launch: "Audio is processed on your device and never uploaded without your permission"
- [ ] `NSMicrophoneUsageDescription` in `Info.plist`: clear, non-generic description for App Review

**Resilience**
- [ ] App backgrounded mid-session: audio continues (`UIBackgroundModes: audio`), timer pauses/resumes, UI restores on foreground
- [ ] FluidAudio init failure: fallback activates silently, banner shown, session continues with `SFSpeechRecognizer`
- [ ] SwiftData write failure: log error, attempt retry once, surface non-blocking error to user
- [ ] Session ends without iCloud configured: local export always succeeds, warning banner persists

**UX hardening**
- [ ] Panic button: full-screen question view accessible from session header (not just script panel)
- [ ] Session timer: optional countdown — user sets target duration in setup sheet, countdown shown in header
- [ ] Transcript auto-scroll: pauses if user scrolls up manually, resumes on "back to bottom" tap
- [ ] Long transcripts: cap live view at last 50 turns for performance; full transcript in `SessionReviewView`

**Accessibility baseline**
- [ ] Dynamic Type: all text views support `.body` and above
- [ ] Minimum tap targets: 44×44pt on all interactive elements (question status tap, ad hoc note button)
- [ ] VoiceOver labels on icon-only buttons (panic button, ad hoc note `+`)

**TestFlight**
- [ ] Archive and upload build to App Store Connect
- [ ] Enable TestFlight internal testing, distribute link to yourself + one other person
- [ ] Dry-run: conduct a real 30-minute interview using the app, export and share the transcript same day

> **Exit criterion (for the entire plan):** You run a real 30-minute interview using the app. You export the transcript and share it with a teammate the same day. The teammate can read it and understand what happened — without attending the session.

---

## 06 — Explicitly Out of Scope

The PRD already scopes these correctly. This list exists so you can close the door quickly when tempted.

| Feature | Phase | Why deferred |
|---|---|---|
| Blank session (no guide) | v2 | Not needed for your own use; team-rollout scenario is Phase 2. Add it back when distributing to teammates. |
| AI coverage scoring (LLM-based, 1–10 per question) | Phase 2 | Needs API key UX, Keychain storage, LLM call plumbing, scoring display in ScriptPanel |
| Post-session AI summary generation | Phase 2 | Depends on AI infrastructure from coverage scoring |
| Per-guide AI prompt customization | Phase 2 | Only needed if default prompt performs poorly in practice |
| Guide branching logic | Phase 2 | Significant UI complexity; zero sessions to validate need against yet |
| macOS client | Phase 3 | Requires separate target or Catalyst; deferred until iOS is stable |
| System audio capture via `ScreenCaptureKit` | Phase 3 | Remote interview support — different audio pipeline entirely |
| Cross-interview synthesis view | Phase 3 | Needs multiple sessions worth of data first |
| Multi-speaker / pair interviews | Phase 3 | Diarization complexity; no validated need in v1 |
| Notion / Confluence / Slack integrations | Phase 4 | Nice-to-have; iCloud folder covers the v1 sharing need |

---

## 07 — Vibe-Coding Notes

**Scaffold the packages before writing any source**
Ask Claude to generate all four `Package.swift` files at once with the correct dependency graph (`App → Features → Services → Data → Domain`). Verify the build succeeds with empty packages before writing a single line of source. A dependency cycle discovered mid-sprint is painful.

**Generate the SwiftData model layer before any feature code**
Give Claude all eight entity definitions and ask for the complete model file with `@Model` annotations. Review relationships carefully — especially the `guideSnapshot` pattern and the `ExportQueueEntry` lifecycle — before writing any coordinator or view code. Bugs here propagate everywhere.

**Incremental persistence is the contract, not a nice-to-have**
Every turn, gap, status change, and note must be written through `SessionRepository` immediately. If you batch writes for convenience and the app crashes mid-interview, you've broken the core reliability promise. When vibe-coding `SessionCoordinator`, verify each callback path ends in a repository write.

**`AVAudioSession` config is subtle**
The background audio mode in the PRD (§4.2) is correct, but `UIBackgroundModes` entries don't always stick when added via Xcode's Capabilities UI. Verify the `Info.plist` file directly contains:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

**SwiftUI previews will break with FluidAudio**
Don't fight it. Use the simulator for anything session-related. Save previews for static views like `GuideEditorView` and `SessionReviewView`.

**`@Observable` + `async`/`await`: watch for `@MainActor`**
EOU callbacks from FluidAudio may arrive off the main thread. Any `@Observable` property mutation that drives UI must happen on `@MainActor`. Annotate `SessionCoordinator` with `@MainActor` at the class level — don't leave it to individual methods.

**Sprint 0 is not optional**
The most common failure mode for a solo build like this is discovering a foundational integration problem in week 3. Sprint 0 surfaces it in day 1 or 2. Skipping it doesn't save time — it borrows it at high interest.
