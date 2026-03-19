# PRD: Interview Partner
**Personal User Interview Companion for iOS & macOS**

---

## Document Info

| Field | Value |
|---|---|
| Author | Jason Wu |
| Status | Draft |
| Last Updated | March 2026 |
| Version | 0.3 |

---

## 1. Overview

### 1.1 Problem Statement

User interviews are one of the highest-signal inputs in product development, but they are frequently under-utilized due to logistics friction. Specifically:

- **Note-taking competes with listening.** Interviewers trying to capture quotes and observations lose eye contact and presence, degrading the quality of the conversation itself.
- **Script compliance is binary and clunky.** Paper or doc-based scripts make it hard to know at a glance whether you've covered the key questions in a flowing, organic conversation.
- **Interviews don't scale across teams.** When a PM or researcher is the bottleneck, the number of interviews is artificially limited. Getting engineers or other teammates to run interviews requires onboarding overhead and often produces inconsistent, hard-to-synthesize notes.
- **Post-interview synthesis is slow.** Turning raw notes into shareable insights requires dedicated time that rarely happens, so findings stay locked in one person's head.

### 1.2 Vision

Interview Partner is a lightweight iOS/macOS app that acts as a quiet, always-on partner during user interviews. It listens, transcribes, tracks your script coverage, and helps you synthesize findings — without getting in the way of the conversation.

### 1.3 Goals

- **G1:** Let interviewers focus entirely on the conversation, not note-taking
- **G2:** Make question coverage visible at a glance during live interviews
- **G3:** Lower the bar for engineers and other non-researchers to run interviews confidently
- **G4:** Produce shareable, synthesized artifacts from each interview with minimal post-processing
- **G5:** Work reliably offline, in quiet rooms, and in cafes

### 1.4 Non-Goals (v1)

- Web or Android clients
- Real-time AI coaching or suggested follow-up questions during interviews
- Video recording or screen capture
- A managed repository / research ops platform (e.g., a full Dovetail replacement)
- Multi-session project management or tagging taxonomy

---

## 2. Users & Context

### 2.1 Primary User: The Interviewer

**Profile:** A PM, engineer, or designer at a tech company who runs occasional user interviews — anywhere from 1 to 10 per month. They have a set of questions they want to hit but value organic, exploratory conversation. They use an iPhone or MacBook in the session.

**Key frustrations:**
- Forgetting to ask something important only to realize it after the session ends
- Spending 30–60 minutes synthesizing notes after the fact
- Notes that are too raw to share with colleagues directly

**Environment:** Mix of in-person (conference rooms, coffee shops) and remote (Zoom/Meet with system audio capture). Connectivity may be unreliable.

### 2.2 Secondary User: The Interview Lead / Researcher

**Profile:** The person (likely Jason) who creates the interview guide, assigns teammates to sessions, and aggregates findings across multiple interviews.

**Key needs:**
- Consistent note structure across sessions run by different teammates
- Fast path from individual sessions to a synthesized cross-interview view
- Lightweight enough that setup doesn't create logistical overhead

---

### 2.3 User Stories

**Interview Prep**
- As an interviewer, I want to create or reuse an interview guide so I can enter a session prepared without starting from scratch.
- As an interviewer, I want to mark questions as must-cover vs. optional so I can make intentional trade-offs when time runs short.
- As an interviewer, I want to add follow-up probes to each question so I have prompts ready if the conversation stalls.
- As an interviewer, I want to add context or hypotheses to the guide so it reflects my specific learning goals for this round.

**During the Interview**
- As an interviewer, I want live transcription with speaker diarization so I don't have to take full notes manually.
- As an interviewer, I want to see at a glance which questions I've covered and which I haven't so I can manage time in the moment.
- As an interviewer, I want to manually update a question's status so I stay in control even when AI scoring disagrees with my judgment.
- As an interviewer, I want to capture a quick freeform note mid-session so I can flag something interesting that doesn't map to any specific question.
- As an interviewer, I want the interface to be glanceable and unobtrusive so it doesn't break rapport with the participant.
- As an interviewer, I want the app to keep working without connectivity so I can run sessions in the field reliably.

**After the Interview**
- As an interviewer, I want an auto-generated summary tied to my key questions so I can quickly share takeaways without spending an hour on synthesis.
- As an interviewer, I want to edit the transcript and correct speaker labels before exporting so the artifact is accurate and shareable.
- As a teammate, I want to review the transcript, notes, and summary without attending the session so I can contribute to synthesis asynchronously.
- As a team lead, I want session files to appear in a shared folder automatically so I can review interviews without chasing people for notes.

---

## 3. Core Concepts

### 3.1 Interview Session

A single interview with one (or more) participants. Contains:
- **Guide:** The script and key questions for the session
- **Transcript:** The live, diarized recording
- **Coverage Map:** Real-time tracking of which questions have been addressed
- **Summary:** AI-generated or manually authored findings artifact

### 3.2 Interview Guide

A reusable template defining:
- Session context (goals, participant profile)
- A set of **Questions** at varying priority levels (see below)
- Optional warm-up/wind-down prompts and probing follow-ups (read-only during session)

Questions are the atomic unit of tracking. Each question has a **priority level** that determines how coverage is weighted and how the interviewer should allocate time:

| Priority | Label | Meaning |
|---|---|---|
| P1 | **Must Cover** | Core research questions. Session is incomplete without these. Coverage tracked prominently. |
| P2 | **Should Cover** | Important but flexible. Cover if time allows after P1s are addressed. |
| P3 | **Nice to Have** | Exploratory or context-setting. Low pressure; skip freely. |

Questions should be specific enough to be measurable but broad enough to be answerable in different ways depending on conversation flow. A typical session has 3–5 Must Cover questions, 2–4 Should Cover, and any number of Nice to Have.

### 3.3 Coverage Status

A per-question signal indicating how well each question has been addressed. Questions have **four states**:

| State | Meaning | Manual | AI |
|---|---|---|---|
| **Not Started** | Not yet discussed | Default | Score 1–3 |
| **Partial** | Mentioned but not fully explored; worth returning to | Tap once | Score 4–6 |
| **Answered** | Sufficient signal captured | Tap twice | Score 7–10 |
| **Skipped** | Deliberately not asked (off-topic, ran out of time, N/A) | Long-press | — |

The interviewer is always in control. Manual status overrides AI scoring at any time. The AI score is a suggestion shown alongside the manual state, not a replacement for it.

### 3.4 Ad Hoc Notes

Freeform observations captured during a session that are not tied to any specific question. Ad hoc notes exist for:
- Interesting tangents that don't map to a question but seem worth capturing
- Non-verbal observations (participant hesitated, laughed, got visibly frustrated)
- Follow-up ideas for future sessions
- Anything the interviewer wants to remember that the transcript alone won't capture

Ad hoc notes appear in the session review and are exported in a dedicated section of the summary. They are not scored for coverage.

---

## 4. Feature Requirements

### 4.1 Live Voice-to-Text Transcription

**Priority:** P0

**Description:**
Continuous transcription of the interview audio, rendered as a scrolling log in the app during the session.

**Requirements:**
- Transcription begins with a single tap ("Start Interview")
- Transcript updates in near real-time (< 3 second lag in normal conditions)
- Supports speaker diarization: automatically labels turns as **Interviewer** vs **Interviewee** (or Speaker A / Speaker B)
- Diarization does not require pre-enrollment — it infers speaker identity from turn patterns and audio characteristics
- Transcript is editable post-session (correct mislabeled speakers, fix proper nouns)
- Audio is processed fully on-device using Apple's speech recognition frameworks (see §4.2); no audio data leaves the device by default

**Speaker Label UX:**
- Speaker labels are color-coded and compact (e.g., left-aligned "You" vs right-aligned "Them")
- User can rename speaker labels post-session before export
- Optionally, user can manually tap to swap the active speaker mid-session if diarization makes an error

**Constraints:**
- On-device model must support English; additional languages are a future consideration
- Transcription quality degrades in noisy environments; this is accepted in v1

---

### 4.2 On-Device Transcription (Privacy & Offline Mode)

**Priority:** P0

**Description:**
All audio capture, transcription, and speaker diarization happen on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio). No audio or transcript data leaves the device unless the user explicitly enables AI features.

**Requirements:**
- App functions fully without internet connectivity — transcription is not degraded offline
- Privacy disclosure shown at first launch: "Audio is processed on your device and never uploaded without your permission"
- A short-lived local audio file may be retained only until the on-device finalization pass completes, then it is deleted by default unless a future explicit opt-in feature says otherwise; the transcript text remains the persistent artifact
- Transcription and diarization begin simultaneously when session starts — no separate pipeline steps visible to the user

**Primary Stack: FluidAudio**

FluidAudio ([FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)) handles the full audio pipeline:
- **Transcription:** On-device speech-to-text, optimized for Apple Neural Engine (ANE) on A-series and M-series chips
- **Speaker diarization:** Automatic speaker segmentation included — no enrollment or pre-configuration required; infers speaker identity from audio patterns
- **Audio session management:** Integrate with `AVAudioEngine` + `AVAudioSession` (`.record` category) for audio routing; pass audio buffers to FluidAudio for processing

**Fallback:**
- `SFSpeechRecognizer` (system, on-device flag) is retained as a fallback if FluidAudio fails to initialize, but will lack diarization capability
- If fallback is active, the UI indicates "Limited transcription mode — speaker separation unavailable"

**Constraints:**
- FluidAudio performance on older A-series chips (pre-A14) is unknown; test on A14+ as minimum supported hardware
- English only in v1; multi-language is a future consideration
- Transcription accuracy degrades in noisy environments — accepted in v1; no special handling

**Audio session configuration:**
```swift
// Audio session setup for FluidAudio integration
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
try audioSession.setActive(true)
// Background audio continuation (screen lock support)
// Requires UIBackgroundModes: "audio" in Info.plist
```

---

### 4.3 Interview Guide & Script Tracking

**Priority:** P0

**Description:**
A structured-but-flexible script view that lets the interviewer reference their Key Questions and track coverage without interrupting conversation flow.

**Requirements:**

**Guide Management (pre-session):**
- Create and name an Interview Guide with a goal/context paragraph
- Add/edit/reorder Questions (plain text, no character limit)
- Assign each question a priority: **Must Cover / Should Cover / Nice to Have**
- Add optional sub-prompts or follow-up probes to each question (collapsed by default during session)
- Add a custom hypothesis or context note to the guide (displayed in session review but not shown live)
- Save guides for reuse across multiple sessions
- Duplicate a guide to create variants

**Live Script View (during session):**
- Persistent compact panel (bottom sheet or side panel) showing Questions grouped by priority (Must Cover first, then Should Cover, then Nice to Have)
- Each question shows its current four-state coverage status: Not Started / Partial / Answered / Skipped
- **Tap** a question to cycle: Not Started → Partial → Answered
- **Long-press** a question to mark it Skipped (with undo via a brief toast)
- Answered questions dim and collapse to the bottom of their priority group; Skipped questions show as muted strikethrough
- Priority badges inline: Must Cover marked distinctly (e.g., filled dot); Should Cover and Nice to Have progressively lighter
- Timer display: elapsed time + optional countdown to session end time
- **Ad Hoc Note button (`+`):** persistent quick-capture control always visible in the script panel footer; tapping opens a one-line text entry overlay that timestamps and saves the note without navigating away from the session
- "Panic button" view: full-screen question list, shows all questions with status and priority badges

**Live Session Screen Layout (iOS portrait — primary target):**

```
┌─────────────────────────────────────┐
│  ← End   P-07 · Engineering   43:12 │  ← Header: participant ID + timer
├─────────────────────────────────────┤
│                                     │
│  [00:00] You                        │
│  Thanks for making time. Just to    │  ← Transcript (~62% of screen)
│  set expectations...                │    Auto-scrolls, fades older text
│                                     │
│  [00:18] Them                       │
│  Sure, sounds good.                 │
│                                     │
│  [00:21] You                        │
│  Let's start with a simple one...   │
│                                     │
├─────────────────────────────────────┤
│  ≡  3 of 4 Must Cover · 12 min left │  ← Script panel header (tappable to expand)
│  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │
│  ● ✅ Morning workflow      9/10    │  ← ● = Must Cover
│  ● ◐  Last build failure   6/10    │  ← ◐ = Partial
│  ● ○  Monorepo vs multi-repo       │  ← ○ = Not Started
│  · ○  Pain in deploy flow          │  ← · = Should Cover
│  · —  Last time you shipped fast   │  ← — = Skipped
│  [+]                       [⊞]    │  ← Ad hoc note + panic view
└─────────────────────────────────────┘
```

**Layout notes:**
- Transcript and script panel are separated by a draggable divider — user can give more screen to whichever they need
- Default split: ~62% transcript / ~38% script panel
- Script panel can be fully collapsed to a thin tab (shows only "N of M Must Cover done") for maximum transcript visibility
- In landscape orientation on iPad: transcript left / script panel right (side by side)
- "Panic view" triggered by `[⊞]` or long-press on script panel header; dismisses with tap anywhere or swipe down
- Ad hoc note overlay is a minimal one-line input anchored above the keyboard; auto-dismisses after submission with no confirmation step

**Coverage Indicators:**
- Manual status icons: ○ = Not Started, ◐ = Partial, ✅ = Answered, — = Skipped
- AI-assisted mode adds a numeric score (1–10) alongside the icon; manual status always takes visual priority
- Session health header shows Must Cover progress separately: "3 of 4 Must Cover done · 12 min left"

---

### 4.4 AI-Assisted Coverage Tracking & Post-Session Summary

**Priority:** P1

**Description:**
Optional integration with a hosted LLM (OpenAI, Anthropic, or user-provided endpoint) to continuously score question coverage against the live transcript and generate a structured findings summary after the interview.

**Setup:**
- User provides their own API key for OpenAI or Anthropic (stored in device Keychain)
- Or: user specifies a compatible OpenAI-API endpoint (e.g., local LLM server, Azure OpenAI, etc.)
- AI features are entirely opt-in; the app is fully functional without them
- Explicit disclosure when AI mode is active: a persistent indicator (e.g., "AI Active — transcript being analyzed")

**Live Coverage Scoring:**
- Transcript is sent to the LLM in rolling windows (e.g., every 60 seconds or on demand via a "Re-analyze" tap)
- LLM is prompted to score each Key Question 1–10 based on transcript so far
- Scores update the Coverage Map in real-time
- Prompt is structured to be deterministic and fast (system prompt + question list + transcript chunk → JSON scores)
- Graceful degradation: if API call fails, fall back to manual mode without disrupting session

**Post-Session Summary Generation:**
- After session ends, user can trigger "Generate Summary"
- Full transcript + Key Questions sent to LLM
- Summary output (structured):
  - **Session metadata:** date, duration, participant pseudonym/ID
  - **Per-question findings:** 1–2 sentence synthesis of what the interviewee said for each Key Question, with a direct quote pulled from transcript
  - **Notable moments:** 3–5 observations the LLM flagged as surprising, contradictory, or high-signal
  - **Open threads:** things the participant mentioned that weren't in the guide but seem worth exploring
- Summary is editable in-app before export
- User can regenerate with different verbosity (brief / detailed)

**Privacy:**
- Transcript text (not audio) is sent to the LLM provider
- User is shown a disclosure before first AI-assisted session: "Your transcript will be sent to [Provider]. Do not include sensitive or identifying information about participants."
- Option to anonymize speaker labels ("Interviewer" / "Participant") before sending

---

### 4.5 Export & Sharing

**Priority:** P0 (iCloud folder auto-export); P1 (manual share sheet)

**Description:**
Sessions and guides are automatically written to a user-selected iCloud folder, making them immediately available in any app that watches that folder — including Obsidian, Google Drive (via iCloud sync bridge), Notion file imports, or shared team folders.

**iCloud Folder Integration:**
- On first launch, user is prompted to select an iCloud folder as their Interview Partner workspace
- This is a standard `UIDocumentPickerViewController` / `NSOpenPanel` folder selection — no special permissions beyond normal iCloud Drive access
- All session exports and guide files are written to this folder automatically at session end
- Folder structure:
  ```
  /InterviewPartner/
  ├── guides/
  │   └── [guide-name].json
  └── sessions/
      └── [YYYY-MM-DD]-[participant-id]/
          ├── transcript.md
          ├── summary.md        (if AI summary generated)
          └── session.json      (structured metadata + coverage map)
  ```
- Compatible workflows out of the box:
  - **Obsidian vault:** place the folder inside an Obsidian vault; transcripts and summaries appear as notes
  - **Google Drive:** use Google Drive's iCloud sync feature; files appear in Drive for teammates
  - **Notion / Confluence:** import markdown files or paste contents

**Manual Share Sheet (additional):**
- Also available from Session Review: iOS/macOS Share Sheet for one-off sharing
- Formats: Markdown, plain text, JSON
- Copy to clipboard (single tap)

**Export contents (configurable in Settings):**
- Full transcript (default: on)
- Summary / findings (default: on if generated)
- Question coverage map (default: on)
- Raw audio file (default: off — opt-in)

---

### 4.6 Blank Session (Guideless Mode)

**Priority:** P1

**Description:**
An escape hatch for unplanned or exploratory conversations where the interviewer doesn't have a Guide loaded. Provides transcription and basic note-taking without question tracking.

**When it's used:**
- An interesting conversation starts spontaneously (hallway conversation, serendipitous Slack DM that turns into a call)
- The interviewer wants to run a completely unstructured exploratory session
- A teammate is doing their first-ever session and doesn't want the overhead of building a guide first

**Requirements:**
- "Start Blank Session" option available from Home screen alongside guide selection
- Blank session provides: live transcription, timer, freeform text note field (pinned above transcript), and manual "mark moment" button that timestamps a highlight in the transcript
- No question tracking, no coverage map, no script panel
- At session end, user is prompted: "Add this to a guide?" — they can retroactively associate the session with an existing guide or create a new guide from this session's transcript (guide creation is manual, not AI-generated in v1)
- Blank sessions are exported the same way as guided sessions: `transcript.md` + `session.json` to iCloud folder; `session.json` will have `"guide_id": null`
- "Mark moment" timestamps appear in the transcript as `[★ 00:12]` — these become anchors in the transcript editor post-session

**Blank session screen layout:**
```
┌─────────────────────────────────────┐
│  ← End   Blank Session      08:44  │
├─────────────────────────────────────┤
│  Note: _________________________   │  ← Pinned freeform note (single line, always visible)
├─────────────────────────────────────┤
│                                     │
│  [00:00] You                        │
│  So you mentioned earlier that...   │
│                                     │
│  [00:18] Them                       │
│  Yeah, the problem is really...     │
│                                     │
│  [★ 00:24]                         │  ← Marked moment
│                                     │
├─────────────────────────────────────┤
│           [★ Mark Moment]          │  ← Single action button at bottom
└─────────────────────────────────────┘
```

### 5.1 Pre-Interview Setup

```
Open app
  → Select or create Interview Guide
    → Review / edit Key Questions
    → Set session duration (optional)
    → Choose AI mode: Off / On (select provider)
  → Tap "Start Interview"
    → App begins recording + transcription
    → Script panel appears
```

### 5.2 During Interview

```
[Conversation in progress]
  → Transcript scrolls automatically
  → Script panel shows question list + coverage
  → Interviewer glances at panel to see uncovered questions
  → Taps question to mark answered (manual) or sees AI score update (AI mode)
  → Timer counts up (or down) in corner
  → If stalled: opens Panic View for full question list
  → Taps "End Interview" when done
```

### 5.3 Post-Interview

```
Session ends
  → Transcript finalized (editable)
  → If AI on: tap "Generate Summary" → review summary → edit as needed
  → Export via Share Sheet (Markdown / text / JSON)
  → Session saved to local history
```

---

## 6. Information Architecture

```
App
├── Home
│   ├── Recent Sessions
│   └── Interview Guides
├── Guides
│   ├── Guide List
│   └── Guide Editor
│       ├── Context / Goal
│       └── Key Questions (ordered list)
├── Active Session (modal, full-screen)
│   ├── Transcript View (primary)
│   ├── Script Panel (persistent overlay)
│   └── Session Controls (timer, end, AI status)
├── Session Review
│   ├── Transcript (editable)
│   ├── Coverage Map
│   ├── Summary (generated / manual)
│   └── Export
└── Settings
    ├── AI Provider (key, model, endpoint)
    ├── iCloud Folder (workspace path selection)
    ├── Transcription (FluidAudio settings, fallback toggle)
    ├── Privacy Preferences
    └── Export Defaults
```

---

## 7. Design Principles

1. **Conversation-first.** The app should never demand attention during a live session. Everything in the UI is glanceable, not read-worthy.
2. **Graceful structure.** The script is a guide, not a gatekeeper. Coverage tracking surfaces information without enforcing order.
3. **Zero-setup for session runners.** A teammate assigned to run an interview should be able to pick up a shared Guide and start in under 60 seconds.
4. **Privacy by default.** All data stays on device unless the user actively enables AI features. No accounts required. iCloud folder sync uses the user's existing iCloud Drive — no new cloud infrastructure.
5. **Output is the artifact.** Every session should produce something shareable. If a session produces nothing exportable, the app failed.

---

## 8. Platform Targets & Technical Constraints

| Dimension | Requirement |
|---|---|
| **iOS target** | iOS 17+ (for on-device speech quality improvements) |
| **macOS target** | macOS 14 Sonoma+ |
| **Language** | Swift / SwiftUI (shared codebase via Swift Multiplatform or separate targets with shared model layer) |
| **Transcription & Diarization** | [FluidAudio](https://github.com/FluidInference/FluidAudio) — ANE-optimized, fully on-device, includes speaker diarization. Primary target: iPhone mic input (in-person sessions). `SFSpeechRecognizer` retained as fallback only. |
| **Remote audio (macOS)** | Deferred to v3. Will use `ScreenCaptureKit` for system audio tap (Zoom/Meet). |
| **AI integration** | OpenAI-compatible REST API; supports Anthropic (`/v1/messages`) and OpenAI (`/v1/chat/completions`) via user-supplied API key (stored in Keychain). Default general-purpose scoring prompt ships in v1; per-guide customization in v2. |
| **Storage** | Local CoreData or SQLite for app state; sessions and guides also written as files to a user-selected iCloud folder (see §4.5). |
| **iCloud folder sync** | User selects a folder once in Settings (e.g., a Google Drive–iCloud sync folder or Obsidian vault). All session exports and guide files are written there automatically. No proprietary sync layer. |
| **Audio** | `AVAudioEngine` + `AVAudioSession`; `.record` mode; microphone permission required. |
| **Networking** | Optional, only for AI features; no baseline network requirement. |

---

## 9. Success Metrics

### Adoption
- % of team members who have run ≥ 1 interview using the app within 30 days of rollout
- Average interviews per active user per month

### Quality
- % of sessions where all Key Questions are marked covered
- Post-session: interviewer self-reported satisfaction with transcription accuracy (1–5)

### Efficiency
- Time from session end to shareable artifact exported (target: < 5 minutes with AI mode)
- Time saved on note-taking vs. prior workflow (self-reported)

### Scale
- Total interview sessions logged across the team per month (target: 3–5× baseline)
- Number of unique interviewers using the app per month

---

## 10. Open Questions

| # | Question | Owner | Priority |
|---|---|---|---|
| OQ-1 | Should guides support branching logic (e.g., show Q5 only if Q4 is answered a certain way)? | Jason | **Resolved:** Yes — defer to v2 |
| OQ-2 | Should we support two-device mode (interviewer on Mac, second mic via iPhone)? | Engineering | **Resolved:** Low priority — defer to v3/v4 |
| OQ-3 | How should multi-interview synthesis work — is a simple export-and-paste-to-Notion workflow sufficient for v1? | Jason | **Resolved:** Sessions auto-export to a user-selected iCloud folder (compatible with Google Drive iCloud sync or Obsidian vault). No manual share step required. |
| OQ-4 | Do we need a team/sharing model so guides can be distributed without manual file transfer? | Jason | **Resolved:** Guides stored and read from the same user-selected iCloud folder as sessions. Sharing = shared iCloud/Google Drive/Obsidian folder. No in-app sync layer needed. |
| OQ-5 | What's the right diarization approach when interviewing via Zoom/Meet with system audio? | Engineering | **Resolved:** Use FluidAudio (FluidInference/FluidAudio) for all audio capture, transcription, and diarization. Primary target: in-person on iPhone. Remote/Mac (system audio via ScreenCaptureKit) deferred to v3. |
| OQ-6 | Should the AI scoring use a fixed prompt or should guide creators be able to customize the scoring rubric? | Jason | **Resolved:** Ship with a well-tuned default general prompt. Per-guide prompt customization added in v2 if default performs poorly in practice. |
| OQ-7 | How do we handle sessions with 2+ interviewees (e.g., pair interviews)? | Jason | **Resolved:** Defer to v3. |

---

## 11. Milestones & Phasing

### Phase 1 — Core Loop (MVP)
*Goal: Solo PM can run and export a well-structured interview session*

- [ ] iOS app with basic session management
- [ ] Live transcription + speaker diarization via FluidAudio (on-device, ANE-optimized)
- [ ] Guide creation + Key Question tracking (manual coverage marking)
- [ ] Session timer
- [ ] iCloud folder workspace setup (folder picker at first launch)
- [ ] Auto-export to iCloud folder on session end: `transcript.md`, `session.json`
- [ ] Manual share sheet (Markdown + plain text)
- [ ] Local session history

### Phase 2 — AI Assist + Team Scale
*Goal: Reduce post-interview work to near-zero; engineers can run interviews without PM bottleneck*

- [ ] OpenAI / Anthropic API key integration (Keychain storage)
- [ ] Live coverage scoring (LLM-based, 1–10 per question, default general prompt)
- [ ] Post-session summary generation (structured findings) → auto-written to iCloud folder as `summary.md`
- [ ] Summary editing + regeneration
- [ ] Guide files written to `guides/` subfolder in iCloud workspace (shareable via Drive/Obsidian)
- [ ] Guide branching logic (conditional questions based on prior answers)
- [ ] Per-guide AI prompt customization (if default prompt proves insufficient in practice)

### Phase 3 — macOS & Remote Interviews
*Goal: Full macOS client; remote interview support via system audio*

- [ ] macOS client (Catalyst or native SwiftUI)
- [ ] System audio capture via `ScreenCaptureKit` for remote interviews (Zoom, Meet, etc.)
- [ ] FluidAudio integration on macOS (or equivalent ANE pipeline for Apple Silicon)
- [ ] Multi-session cross-interview synthesis view (manual + AI-assisted)
- [ ] Support for 2+ interviewees / pair interviews (multi-speaker diarization)

### Phase 4 — Polish & Integrations
*Goal: Fit naturally into team research workflows*

- [ ] Notion / Confluence direct export integration
- [ ] Two-device mode (interviewer on Mac, second iPhone mic) — v3/v4 candidate
- [ ] Custom AI scoring rubric per guide (if not addressed in Phase 2)
- [ ] Internationalization / additional transcription language support

---

## 12. Appendix

### A. Competitive Landscape

| Tool | Strengths | Gaps for this use case |
|---|---|---|
| Otter.ai | Good transcription, web-first | No script tracking, cloud-only, not research-specific |
| Dovetail | Strong synthesis, tagging | No live transcription, heavy ops overhead, expensive |
| Lookback | Video + annotation | Requires participants to install something, heavy |
| Notion AI | Flexible, familiar | Manual, no audio, no script tracking |
| Apple Notes + Whisper | Free, private | No structure, no coverage tracking, DIY |

### B. Question Design Guidelines
*(for guide authors)*

**Good questions at any priority level:**
- Are answerable in 30–90 seconds of natural conversation
- Surface a specific belief, behavior, or pain point — not a preference or feature request
- Can be answered indirectly (a story or tangent may still answer the question)
- Are written from the user's perspective, not the product's

**Choosing the right priority:**

| Priority | Use when... | Typical count |
|---|---|---|
| **Must Cover** | You cannot leave the session without signal on this. Missing it means the session was incomplete for your research goal. | 3–5 |
| **Should Cover** | Important context that strengthens your findings, but the session is still useful without it. | 2–4 |
| **Nice to Have** | Exploratory or confirmatory. Cover only if the conversation naturally goes there. | Any |

A session with 10 Must Cover questions is not a semi-structured interview — it's a survey. If you find yourself marking everything Must Cover, reconsider what your actual non-negotiable learning goals are.

**Examples:**
- ✅ Must Cover: "Walk me through the last time a build failure cost you significant time."
- ✅ Should Cover: "How do you usually decide whether to ask for help or debug solo?"
- ✅ Nice to Have: "If you could change one thing about your CI setup tomorrow, what would it be?"
- ❌ Any priority: "Would you use a feature that does X?" (leading — answers the wrong question)
- ❌ Any priority: "How do you feel about the current developer experience?" (too broad to score or act on)

---

## 13. File Format Specifications

All files written to the iCloud workspace are plain text or JSON — human-readable, portable, and compatible with any tool that can open a folder. No binary formats, no proprietary schemas.

### 13.1 Guide File Format (`.json`)

Stored at: `InterviewPartner/guides/[guide-slug].json`

```json
{
  "schema_version": "1.0",
  "id": "uuid-v4",
  "name": "Engineering Workflow Discovery",
  "created_at": "2026-03-17T10:00:00Z",
  "updated_at": "2026-03-17T10:00:00Z",
  "context": "Understanding how engineers currently navigate CI/CD friction points. Focus on actual workflow, not opinions on tooling.",
  "target_duration_minutes": 45,
  "questions": [
    {
      "id": "q1",
      "order": 1,
      "text": "Walk me through what your morning looks like on a typical coding day.",
      "priority": "must_cover",
      "type": "key",
      "probes": [
        "What's the first thing you open?",
        "Where do you usually get stuck before lunch?"
      ],
      "branch": null
    },
    {
      "id": "q2",
      "order": 2,
      "text": "Tell me about the last time a build failure made you want to close your laptop.",
      "priority": "must_cover",
      "type": "key",
      "probes": [
        "How long did it take to resolve?",
        "Did you ask for help, or go it alone?"
      ],
      "branch": null
    },
    {
      "id": "q3",
      "order": 3,
      "text": "Do you mostly work in a monorepo or multiple repos?",
      "priority": "should_cover",
      "type": "screener",
      "probes": [],
      "branch": {
        "if_answer_contains": ["monorepo", "mono"],
        "show_question_id": "q4a",
        "else_show_question_id": "q4b"
      }
    }
  ],
  "wrap_up_prompts": [
    "Is there anything about your workflow you wish I'd asked about?",
    "If you could change one thing about your dev environment tomorrow, what would it be?"
  ],
  "ai_scoring_prompt_override": null
}
```

**Field notes:**
- `priority` values: `"must_cover"`, `"should_cover"`, `"nice_to_have"`. Controls visual weight in live session and how coverage is reported.
- `type` can be `"key"` (tracked in coverage), `"screener"` (binary branch trigger), or `"context"` (warm-up, not scored)
- `branch` is null in v1; the field is present in the schema from day one so v2 branching doesn't require a migration
- `ai_scoring_prompt_override` is null in v1; populated in v2 when per-guide prompts are supported
- `probes` are shown collapsed during live sessions; the interviewer taps a question to reveal them

---

### 13.2 Session Transcript File (`transcript.md`)

Stored at: `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/transcript.md`

Human-readable Markdown. Designed to be dropped directly into an Obsidian note or Notion page without modification.

```markdown
# Interview Transcript
**Guide:** Engineering Workflow Discovery
**Date:** 2026-03-17
**Duration:** 43 minutes
**Participant ID:** P-07
**Interviewer:** Jason Wu
**Transcription:** FluidAudio (on-device)
**AI Assist:** Anthropic Claude (claude-sonnet-4)

---

## Coverage Summary

| # | Question | Priority | Status | AI Score |
|---|---|---|---|---|
| Q1 | Walk me through what your morning looks like... | Must Cover | ✅ Answered | 9/10 |
| Q2 | Tell me about the last time a build failure... | Must Cover | ◐ Partial | 6/10 |
| Q3 | Do you mostly work in a monorepo or multiple repos? | Should Cover | ✅ Answered | 10/10 |

**Must Cover: 1 of 2 fully answered, 1 partial · Should Cover: 1 of 1 answered**

---

## Transcript

**[00:00]** **You:** Thanks for making time. Just to set expectations — this is about 45 minutes, pretty conversational. No right or wrong answers. I'll be listening more than talking.

**[00:18]** **Them:** Sure, sounds good.

**[00:21]** **You:** Let's start with a simple one. Walk me through what your morning looks like on a typical coding day.

**[00:28]** **Them:** So usually I'm checking Slack first, honestly before I even open my IDE. There's always something from the overnight CI runs...
```

**Design notes:**
- Speaker labels are `**You:**` and `**Them:**` by default; user can rename before export (e.g., to `**Interviewer:**` / `**P-07:**` for anonymization)
- Timestamps are relative to session start, not wall clock, to protect participant scheduling privacy
- Coverage table is inserted at the top so the document is immediately useful when shared without reading the full transcript

---

### 13.3 Session Summary File (`summary.md`)

Stored at: `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/summary.md`

Generated by LLM post-session (or written manually if AI is off). Same folder as transcript so they travel together.

```markdown
# Interview Summary
**Guide:** Engineering Workflow Discovery
**Date:** 2026-03-17
**Participant ID:** P-07
**Generated by:** Claude (claude-sonnet-4) · Reviewed by Jason Wu

---

## Key Findings

### Q1 — Walk me through what your morning looks like...
Participant starts their day in Slack, not their IDE. Monitors overnight CI results before writing any code. Described the period between opening Slack and starting actual coding as "tax I pay every morning." Typically 20–40 minutes.

> "There's always something from the overnight CI runs. I feel like I'm a janitor before I'm an engineer."

### Q2 — Tell me about the last time a build failure...
Described a specific incident two weeks prior where a flaky integration test blocked a PR for 3 days. Didn't escalate for 2 days because he assumed it was his fault. Resolved by a senior engineer in 20 minutes once he asked.

> "I just assumed I'd broken something. Turns out it had been failing on and off for weeks."

### Q3 — Monorepo or multiple repos?
Monorepo. Has opinions. Branched to monorepo-specific follow-ups.

---

## Notable Moments

- **Shame asymmetry:** Participant visibly hesitated before admitting he waited 2 days to ask for help. This suggests a blame culture signal worth probing in future sessions.
- **"Janitor before engineer"** — this framing came up unprompted and is quotable for stakeholder presentations.
- Strong preference for async communication; mentioned Slack but expressed fatigue with it in the same breath.

---

## Open Threads
*(Topics raised that weren't in the guide)*

- Mentioned a homegrown internal tool his team built to triage CI failures — worth understanding if this is widespread or a one-off
- Brought up "deployment confidence" as a separate anxiety from build failures; not in current guide

---

## Ad Hoc Notes
*(Captured live during session — not tied to a specific question)*

- **[13:23]** Mentioned an internal tool his team built to triage CI failures — worth probing in a future session
- **[25:40]** Visibly hesitated before admitting he waited 2 days to ask for help — possible blame culture signal
```

---

### 13.4 Session Metadata File (`session.json`)

Stored at: `InterviewPartner/sessions/[YYYY-MM-DD]-[session-id]/session.json`

Machine-readable session record. Intended for future tooling (cross-interview synthesis, import into other tools).

```json
{
  "schema_version": "1.0",
  "session_id": "uuid-v4",
  "guide_id": "uuid-v4",
  "guide_name": "Engineering Workflow Discovery",
  "date": "2026-03-17",
  "started_at": "2026-03-17T14:02:11Z",
  "ended_at": "2026-03-17T14:45:38Z",
  "duration_seconds": 2607,
  "participant_id": "P-07",
  "interviewer": "Jason Wu",
  "transcription_engine": "FluidAudio",
  "ai_assist_enabled": true,
  "ai_provider": "anthropic",
  "ai_model": "claude-sonnet-4",
  "coverage": [
    {
      "question_id": "q1",
      "question_text": "Walk me through what your morning looks like...",
      "priority": "must_cover",
      "status": "answered",
      "ai_score": 9,
      "marked_manually": false,
      "marked_at_seconds": null
    },
    {
      "question_id": "q2",
      "question_text": "Tell me about the last time a build failure...",
      "priority": "must_cover",
      "status": "partial",
      "ai_score": 6,
      "marked_manually": true,
      "marked_at_seconds": 1820
    },
    {
      "question_id": "q3",
      "question_text": "Do you mostly work in a monorepo or multiple repos?",
      "priority": "should_cover",
      "status": "answered",
      "ai_score": 10,
      "marked_manually": true,
      "marked_at_seconds": 612
    }
  ],
  "ad_hoc_notes": [
    {
      "id": "note-1",
      "timestamp_seconds": 843,
      "text": "Mentioned an internal tool his team built to triage CI failures — worth probing in future sessions"
    },
    {
      "id": "note-2",
      "timestamp_seconds": 1540,
      "text": "Visibly hesitated before admitting he waited 2 days to ask for help — possible blame culture signal"
    }
  ],
  "tags": [],
  "notes": ""
}
```

---

## 14. Default AI Scoring Prompt

This is the system prompt used for both live coverage scoring and post-session summary generation in v1. It is fixed and not user-configurable until v2.

### 14.1 Live Coverage Scoring Prompt

```
You are an assistant helping score how well a user interview has addressed a set of research questions.

You will be given:
1. A list of questions from the interview guide, each with an ID and priority level (must_cover, should_cover, nice_to_have)
2. A partial transcript of the interview so far

For each question, return a JSON object with:
- "question_id": the ID from the guide
- "score": integer 1–10 representing how thoroughly this question has been addressed
  - 1–3: Not addressed or only mentioned in passing
  - 4–6: Partially addressed; some useful signal but incomplete
  - 7–9: Well addressed; interviewer has sufficient data on this question
  - 10: Thoroughly addressed with specific examples or stories
- "suggested_status": one of "not_started", "partial", "answered"
  - Map score 1–3 → "not_started", 4–6 → "partial", 7–10 → "answered"
  - Do NOT suggest "skipped" — that is a deliberate interviewer action only
- "reasoning": one sentence explaining the score (used for debugging, not shown to user)

Prioritize accuracy on must_cover questions. If a must_cover question is only partially addressed and time appears short, note this in the reasoning field.

Return ONLY a valid JSON array. No preamble, no markdown, no explanation.

Example output:
[
  {"question_id": "q1", "score": 8, "suggested_status": "answered", "reasoning": "Participant described morning workflow in detail with specific tools mentioned."},
  {"question_id": "q2", "score": 5, "suggested_status": "partial", "reasoning": "Build failures mentioned briefly but no specific incident described yet."},
  {"question_id": "q3", "score": 1, "suggested_status": "not_started", "reasoning": "Monorepo vs multi-repo not discussed yet."}
]
```

### 14.2 Post-Session Summary Prompt

```
You are a UX research assistant helping synthesize findings from a user interview.

You will be given:
1. An interview guide with questions, each labeled with a priority (must_cover, should_cover, nice_to_have) and final status (not_started, partial, answered, skipped)
2. The full interview transcript with speaker labels (You / Them)
3. A list of ad hoc notes captured by the interviewer during the session (timestamped, not tied to specific questions)

Your task is to produce a structured research summary in Markdown with the following sections:

## Key Findings
Write findings grouped by priority. Start with must_cover questions, then should_cover, then nice_to_have.

For each question:
- If status is "answered": write 2–4 sentences summarizing what the participant said. Pull one direct quote from the transcript (under 20 words) that best represents their answer.
- If status is "partial": write 1–2 sentences on what was captured, and flag it as incomplete: "(Partial — may benefit from follow-up)"
- If status is "not_started": write one line: "(Not addressed in this session)"
- If status is "skipped": write one line: "(Skipped by interviewer)"

Be factual and specific. Do not editorialize beyond what the transcript supports. Do not reference the interviewer's questions — focus on what the participant revealed.

## Notable Moments
List 3–5 observations that were:
- Surprising or counterintuitive
- Emotionally charged or delivered with strong affect
- Contradicted common assumptions about this user type
- Said unprompted (not in direct response to a question)
Format each as a short bold title followed by 1–2 sentences of context.

## Open Threads
List topics the participant raised that were NOT in the interview guide but seem worth exploring in future sessions. One sentence per item.

## Interviewer Notes
Reproduce the ad hoc notes from the session verbatim, preserving timestamps. Do not interpret or synthesize them — present them as captured.

Rules:
- Write in third person ("The participant said..." not "You asked...")
- If a must_cover question was not answered or only partial, note this prominently at the top of Key Findings as a flag: "⚠️ [Question text] — not fully addressed"
- Return Markdown only. No preamble.
```

### 14.3 Prompt Design Rationale

- **JSON-only output for live scoring** removes parsing fragility; the app expects a strict array and degrades gracefully if parsing fails
- **`suggested_status` field** gives the app a pre-mapped four-state value so it doesn't have to re-derive state from a numeric score — reduces client-side logic and drift between scoring and display
- **"Skipped" is interviewer-only** — the model cannot suggest skipping a question; that's a deliberate human decision. This prevents the AI from silently eliding must-cover questions it found ambiguous
- **Priority-aware reasoning** in the scoring prompt asks the model to flag must-cover gaps in the reasoning field — useful debugging signal for v2 prompt tuning
- **Must-cover gap flag in summary** (`⚠️`) ensures that if a key question wasn't addressed, the artifact calls it out prominently rather than burying it in the findings structure
- **Ad hoc notes passed verbatim to summary** — the model is explicitly told not to interpret them, only reproduce them. This preserves the interviewer's raw signal without laundering it through AI paraphrase
- **Reasoning field** in scoring is logged locally for debugging but never shown in the UI — gives signal for v2 prompt tuning without cluttering the interviewer's view
- **Explicit score rubric** (1–3 / 4–6 / 7–9 / 10) anchors the model to consistent calibration across sessions and interviewers
- **"Do not editorialize" rule** in the summary prompt keeps findings defensible when shared with skeptical stakeholders
- **Quote length cap** (under 20 words) forces the model to find tight, usable quotes rather than pulling whole paragraphs

---

## 15. Edge Cases & Error Handling

### 15.1 Live Session Failures

| Scenario | Behavior |
|---|---|
| FluidAudio fails to initialize | Show error before session starts. Offer to proceed without transcription (manual note mode). Never silently start without transcription. |
| FluidAudio drops mid-session | Show subtle persistent warning banner: "Transcription paused." Do NOT interrupt the interview with a modal. Resume automatically when audio recovers. Gap in transcript is marked `[transcription unavailable 00:12–00:18]`. |
| iPhone locks during session | `AVAudioSession` background audio mode keeps transcription running. Screen lock does not interrupt recording. |
| App backgrounded during session | Same as above — recording and transcription continue in background. Banner notification confirms active session. |
| Storage full (iCloud or local) | Warning shown before session starts if < 100MB available. Mid-session: transcript buffered in memory; write to disk retried every 30 seconds. User notified post-session if export failed. |
| iCloud folder unavailable (offline, permissions revoked) | Export queued locally. On next app open with iCloud available, queued exports are written automatically. User sees a "Pending export" badge on affected sessions. |

### 15.2 AI Feature Failures

| Scenario | Behavior |
|---|---|
| API key invalid or expired | Gracefully disable AI mode, show Settings prompt post-session. Session proceeds normally in manual mode. |
| LLM API call times out (> 10s) | Retry once silently. If second attempt fails, skip this scoring interval. Coverage scores remain at last successful values. No modal. |
| LLM returns malformed JSON | Log error locally. Skip update. Do not display a score update this interval. |
| LLM returns scores outside 1–10 range | Clamp to range on the client. Log as anomaly. |
| Summary generation fails | Show error in Session Review with a "Retry" button. Transcript is always available regardless. |
| User hits API rate limit | Show warning: "AI scoring paused — rate limit reached." Offer to queue a single summary call for post-session. |

### 15.3 Transcription Quality

| Scenario | Behavior |
|---|---|
| Heavy background noise | Transcription continues but accuracy degrades. No special handling — this is a physical environment problem. Consider a future "noise level" indicator using audio RMS. |
| Overlapping speech | FluidAudio handles overlapping segments with confidence scores. Below a confidence threshold, segment is labeled `[unclear]` rather than attributed to a speaker. |
| Proper nouns / technical terms | No custom vocabulary in v1. User can correct post-session in the transcript editor. Custom vocabulary list is a v2 candidate. |
| Very long silence (> 2 min) | Transcription continues. No timeout. |

---

## 16. Onboarding & Teammate Setup

A core goal is that an engineer or designer with no prior interview experience can be assigned a Guide, open the app, and run a session within 5 minutes. This section defines the first-run experience.

### 16.1 First-Run Flow (New User)

```
App install
  → Welcome screen (1 screen, no carousel)
     "Interview Partner helps you run better user interviews.
      Everything stays on your device."
     [Get Started]
  → Microphone permission prompt (system)
  → iCloud folder setup
     "Choose a folder where your interviews and guides will be saved.
      This can be a Google Drive or Obsidian folder synced via iCloud."
     [Choose Folder]  [Skip for now → saves to app's Documents directory]
  → AI setup (optional, skippable)
     "Want AI to help track coverage and write summaries?"
     [Set Up AI]  [Not now]
       → If Set Up AI: select provider (Anthropic / OpenAI / Custom endpoint)
         → Enter API key → key validated with a test ping → confirmation
  → Home screen
     "You're ready. Start with a guide or jump into a blank session."
```

### 16.2 Returning User: Teammate Setup

When a teammate opens a Guide shared via iCloud/Drive folder, they see:

```
Guide detected in your Interview Partner folder
  "[Guide Name]"
  Created by: Jason Wu · Last updated: March 17

  [Open Guide]  [Dismiss]
```

If they don't have the app: the Guide JSON file is human-readable. In a pinch, a teammate can run the session with just the JSON file open in any text editor. The structure is intentionally readable as a plain document.

### 16.3 Pre-Interview Checklist (shown before every session)

A lightweight confirmation screen before recording starts:

```
Ready to start?

✓ Microphone access: On
✓ Guide loaded: "Engineering Workflow Discovery" (7 questions)
✓ iCloud folder: /Obsidian Vault/Interviews/
○ AI assist: Off  [Enable]
○ Session duration: Not set  [Set timer]

Participant ID (optional): [P-07         ]

[Start Interview]
```

- Green checkmarks for items confirmed; circle for optional items
- Participant ID is a free-text field that becomes the folder/file label — not linked to any identity system
- Starting without setting duration is fine; the timer just counts up

### 16.4 Interviewer Quick Reference Card

A separate one-page document (PDF/Markdown) for sharing with teammates who will run sessions. Covers:

1. **Before the interview:** Load the guide, set participant ID, confirm mic is on
2. **During:** Glance at the script panel — green = covered, gray = not yet. Don't force it.
3. **If you get stuck:** Tap the question list icon for the full panic view
4. **Ending:** Tap "End Interview." Wait for export confirmation before closing the app.
5. **After:** Files appear in the shared folder automatically. Nothing else needed.

---

## 17. Accessibility

### 17.1 Live Session View

- All interactive elements meet WCAG AA touch target minimums (44×44pt)
- Coverage indicators use both color AND a text/icon signal (not color-only) — critical for colorblind interviewers
- Transcript text is resizable via system Dynamic Type; minimum readable at the largest accessibility size
- "Panic view" (full question list) is reachable via a visible button, not a gesture-only affordance
- VoiceOver: active session screen is marked with `accessibilityViewIsModal = true` to suppress background noise from VoiceOver during an interview

### 17.2 General

- All navigation is keyboard-accessible on macOS
- Haptic feedback (iOS) on question marked as answered — confirms the tap without requiring a glance at the screen
- High contrast mode supported via system `UIColor` semantics (no hardcoded hex colors in UI layer)
- Session timer readable at arm's length (minimum 24pt, bold weight)

---

## 18. Privacy & Data Handling

A consolidated reference for all data types, where they live, and what leaves the device under what conditions. This section governs engineering decisions; if a proposed implementation creates a new data flow not listed here, it must be reviewed and this section updated first.

### 18.1 Data Inventory

| Data Type | Where Stored | Leaves Device? | Conditions |
|---|---|---|---|
| Audio (raw) | In-memory only during session | Never | Audio is processed in-flight by FluidAudio; not persisted to disk unless user explicitly enables "save audio" in Settings |
| Transcript text | Local SQLite + iCloud folder (user-selected) | Only with AI enabled | Sent to LLM provider (Anthropic/OpenAI) for live scoring and summary generation; never sent to Anthropic or Apple infrastructure automatically |
| Interview Guide (JSON) | Local SQLite + iCloud folder | Never | Stays in iCloud folder; not transmitted anywhere by the app |
| Session metadata (JSON) | Local SQLite + iCloud folder | Never | Same as guides |
| AI Summary (Markdown) | iCloud folder | Never (after generation) | Transcript is sent to generate it; result is stored locally; summary itself is not re-transmitted |
| API keys | iOS Keychain / macOS Keychain | Never | Keys never written to disk outside Keychain; never included in exports or logs |
| Participant ID | Session JSON + transcript header | Only within exports | Participant ID is a free-text label set by the interviewer — no PII is collected or inferred by the app |

### 18.2 What "AI Enabled" Means for Data

When the user enables AI mode for a session:
- The **transcript text** for that session is sent to the configured LLM provider (Anthropic or OpenAI) in rolling chunks during the session, and in full at summary generation time
- The user is shown a disclosure before their first AI-enabled session — this acknowledgment is stored locally so it's not shown again
- The disclosure states: *"When AI assist is on, your interview transcript will be sent to [Provider Name] to score question coverage and generate a summary. Audio is never sent. Do not include personally identifying information about your participants."*
- AI mode is a per-session toggle — enabling it for one session does not enable it by default for future sessions (user must confirm at each session start)

### 18.3 iCloud Folder

The iCloud folder is the user's own storage — the app writes files there, but this is no different from saving a file in Finder. Apple's standard iCloud terms apply. The app does not have a backend that reads from or indexes the user's iCloud folder.

### 18.4 No Analytics, No Telemetry

Interview Partner collects no usage analytics, crash reporting, or telemetry in v1. The rationale: this app is used during sensitive conversations with research participants. Any background network activity, even anonymized, is inappropriate. Crash logs are collected only via Apple's opt-in system (standard Xcode/TestFlight crash reporting, which the user controls at the OS level).

If telemetry is added in a future version, it will be:
- Opt-in only
- Limited to aggregate session counts (no content, no participant data)
- Documented in this section before implementation

### 18.5 Participant Consent

The app does not manage participant consent — this is the interviewer's responsibility. However, the pre-interview checklist (§16.3) includes a reminder field: "Have you confirmed the participant is comfortable being recorded?" This is informational only; the app does not gate session start on a consent confirmation.

---

## 19. Permissions & App Store Considerations

### 19.1 Required Permissions

| Permission | iOS Key | When Requested | Rationale |
|---|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` | First time user taps "Start Interview" (or "Start Blank Session") | Core functionality — transcription requires mic access |
| iCloud Drive | Implicit via `UIDocumentPickerViewController` | When user selects iCloud folder in onboarding or Settings | Required to write session exports and guides to user-selected iCloud folder |
| Speech Recognition | `NSSpeechRecognitionUsageDescription` | First time transcription starts (if SFSpeechRecognizer fallback used) | Fallback path only; not required if FluidAudio handles all transcription |

**What is NOT required:**
- Location — never requested
- Contacts — never requested
- Camera — never requested
- Notifications — not needed in v1 (background audio session is sufficient)
- Face ID / Touch ID — not used (API keys protected by Keychain, not biometric gates)

### 19.2 Background Modes (Info.plist)

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Required so that transcription continues when the iPhone screen locks mid-session. Without this, `AVAudioSession` is interrupted by screen lock and the session is silently broken — a critical failure mode.

### 19.3 Privacy Manifest (PrivacyInfo.xcprivacy)

Required as of iOS 17 / Xcode 15 for App Store submission. Fields:

```xml
NSPrivacyTracking: NO
NSPrivacyTrackingDomains: []
NSPrivacyCollectedDataTypes:
  - AudioData: collected on-device, not linked to identity, not used for tracking
NSPrivacyAccessedAPITypes:
  - NSPrivacyAccessedAPICategoryMicrophone
  - NSPrivacyAccessedAPICategoryFileTimestamp (for session file creation dates)
```

### 19.4 App Store Category & Rating

- **Primary category:** Productivity
- **Secondary category:** Business
- **Age rating:** 4+ (no user-generated content visible to others, no third-party services required)
- **App Store description framing:** Position as a professional research tool, not a general-purpose recording app — this affects App Review scrutiny of the microphone usage justification

### 19.5 TestFlight Distribution (Team Rollout)

For internal team rollout prior to App Store submission:
- Distribute via TestFlight internal testing (up to 100 testers, no review required)
- Use a single shared TestFlight link distributed via Slack/email
- Testers need an Apple ID — no enterprise certificate or MDM required
- Build expiry: 90 days per TestFlight build; plan to re-distribute before expiry during active use

---

---

## 20. Risks & Tradeoffs

### Risk 1: Too much structure harms conversation quality
The guide panel, coverage indicators, and timer could cause interviewers — especially new ones — to follow the checklist mechanically instead of listening deeply. An interview where every question is answered but the participant felt interrogated is a worse outcome than one where 6 of 7 questions were covered organically.

**Mitigation:**
- Keep the live UI glanceable, not readable. The script panel should never demand attention.
- The guide is framed as a safety net, not a sequence to execute.
- Onboarding copy and the quick reference card (§16.4) explicitly reinforce this: "Don't force it."
- Consider adding a post-session satisfaction field for the interviewer to self-report conversation quality, independent of coverage score.

---

### Risk 2: Unreliable diarization reduces trust in AI features
If FluidAudio regularly misattributes speaker turns — especially in noisy environments or when both speakers have similar vocal characteristics — interviewers will stop trusting the AI coverage scores and the summary. Once trust is broken, it's hard to recover.

**Mitigation:**
- Manual status always overrides AI scoring and is the primary indicator in the UI. AI is a suggestion, never a gate.
- Post-session transcript editing makes speaker correction low-friction.
- Diarization errors are visually distinct (labeled `[unclear]`) rather than confidently mislabeled.
- Track diarization correction rate as a reliability metric (§9); if it exceeds ~15% of turns, treat as a product blocker.

---

### Risk 3: Privacy concerns block team adoption
Some interviews touch sensitive topics — user frustrations with leadership, compensation, internal tooling failures. Teammates may be reluctant to use a tool that could send this content to an external LLM provider, even with opt-in disclosure.

**Mitigation:**
- The core product is fully functional without any hosted AI. Transcription, coverage tracking, and export all work offline and on-device.
- AI mode shows a persistent, visible indicator when active — no silent background uploads.
- Transcript text (not audio) is what's sent, and only when the user explicitly triggers it.
- The iCloud folder model means there's no app backend that stores or indexes session content.
- Consider a "scrub before send" step in v2: show the user a preview of the transcript that will be sent before the first AI call in a session.

---

### Risk 4: AI coverage scoring is misleading
The model may mark a must-cover question as "answered" when the participant's response was superficial, off-topic, or a deflection. An interviewer who trusts the score and moves on has missed something important — and won't know until synthesis.

**Mitigation:**
- AI scores are suggestions. The manual four-state status is always the primary control.
- The "Partial" state exists precisely for this: the interviewer can mark a question partial when the AI says answered, surfacing the gap without overriding the transcript record.
- The summary prompt is instructed to pull a supporting quote for every answered question — a quote that doesn't quite fit is a signal that the score was inflated.
- Track agreement rate between interviewer manual status and AI suggested status as a metric (§9); persistent disagreement suggests prompt needs tuning.

---

### Risk 5: The app becomes too heavyweight for casual use
Over time, as features accumulate — branching, per-guide AI prompts, team workspaces, cross-session synthesis — the app could develop the same operational overhead it was designed to eliminate. New teammates opening the app for the first time encounter a complex tool, not the quiet copilot the vision describes.

**Mitigation:**
- The blank session path (§4.6) must always exist and be prominently accessible. No guide required to start recording.
- Phase 2+ features are additive, not gatekeeping. A user who ignores guides, AI, and export workflows should still get value from transcription alone.
- Evaluate each new feature against the 60-second rule: can a first-time user run a session within 60 seconds of opening the app? If a new feature threatens that, it needs to be hidden or deferred.

---

### Risk 6: iCloud folder sync creates confusion for teammates
If two team members write session files to the same shared folder simultaneously, or if a guide file is updated on one device while another is in a session, there's potential for conflict, stale reads, or confusion about which version is canonical.

**Mitigation:**
- Each session is written to its own dated subfolder (`/sessions/YYYY-MM-DD-[session-id]/`) — no two sessions share a write path.
- Guides are read at session-start, not continuously synced during a session. The guide loaded at "Start Interview" is the version used, regardless of subsequent changes to the file.
- In v1, last-write-wins for guide files. Conflict resolution UI is a v2 consideration if team usage reveals this as a real pain point.

---

## 21. Future Opportunities

These are not committed roadmap items. They are promising directions worth tracking as the core product matures.

### Cross-Interview Synthesis
- Compare multiple interviews by guide or theme — identify which must-cover questions consistently get shallow answers across sessions
- Automated pattern extraction: surface recurring phrases, sentiments, or topics across a set of sessions
- Snippet library: save notable quotes from transcripts and tag them for retrieval during synthesis or stakeholder presentations

### Smarter Live Assistance
- Suggest follow-up probes in real time based on a gap between what the participant said and what the question was looking for (requires streaming LLM call during session — higher latency and privacy bar)
- Detect when a must-cover question is likely to go unanswered given remaining time, and surface a gentle prompt to the interviewer
- Ambient mode: a minimal HUD that shows only the timer and a "next uncovered must-cover" label — maximum attention on the participant, minimum on the screen

### Richer Guide Authoring
- Branching logic per question (v2 — already in plan)
- Guide versioning: track changes to a guide over time and annotate which sessions used which version
- Hypothesis tracking: attach pre-session hypotheses to questions and flag post-session whether the transcript confirmed, contradicted, or left them open
- Guide library: community or team-shared templates for common research archetypes (discovery, usability, satisfaction)

### Remote Interview Support
- macOS system audio capture via `ScreenCaptureKit` for Zoom/Meet sessions (v3 — already in plan)
- Two-speaker mode where interviewer audio and participant audio are captured on separate channels — cleaner diarization, better quality
- Two-device mode: Mac as primary capture device, iPhone as secondary mic for noisy environments (v3/v4)

### Workflow Integrations
- Direct push to Notion, Confluence, or Google Docs post-session
- Slack summary sharing: post a condensed version of the summary to a channel automatically
- Lightweight CRM hook: attach session metadata to a participant record in an external system (e.g., tag a contact in HubSpot or Notion database with a session link)

---

## 22. Revision History

| Version | Date | Author | Summary of Changes |
|---|---|---|---|
| 0.1 | March 2026 | Jason Wu | Initial draft |
| 0.2 | March 2026 | Jason Wu | OQ-1 through OQ-7 resolved; FluidAudio as primary stack; iCloud folder as sharing model; file format specs; AI prompt specs; edge cases; onboarding; accessibility added |
| 0.3 | March 2026 | Jason Wu | §4.2 rewritten for FluidAudio; §4.3 live session layout added; §4.6 Blank Session defined; §18 privacy & data handling; §19 permissions & App Store considerations added |
| 0.4 | March 2026 | Jason Wu | User stories (§2.3); question priority levels (Must Cover / Should Cover / Nice to Have); four-state question status (Not Started / Partial / Answered / Skipped); ad hoc notes; all updated in core concepts, feature specs, wireframe, file schemas, and AI prompts. Risks & Tradeoffs (§20) and Future Opportunities (§21) added. |
