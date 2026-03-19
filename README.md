# InterviewPartner - iOS App

## Background

There are a thousand user interview apps, but this one is mine. This app is intended to be a personal user interview companion for note-taking and in-conversation guidance — built around a loose script that keeps you on track without getting in your way. It has just enough structure to be useful and just enough flexibility to follow conversations wherever they organically go. I also want it to scale: as I bring more engineers from my team into the interview process, it should make it easy to share notes, synthesize findings, and surface insights across the team.

- Live voice-to-text transcription with speaker diarization, automatically distinguishing interviewer from interviewee
- On-device transcription for privacy and reliability in low-connectivity environments
- A loose interview script with key questions to answer, with live tracking so you always know which questions you've covered during a timeboxed conversation
- Optional LLM integration (OpenAI, Anthropic, etc.) to passively monitor the transcript, score question coverage in real time (1–10), and generate a findings summary after the interview wraps
- iOS and macOS first

<img width="295" height="639" alt="image" src="https://github.com/user-attachments/assets/f8ffbc06-f972-4628-8fb1-6d66721821b7" />
<img width="295" height="639" alt="image" src="https://github.com/user-attachments/assets/ed667f04-7d6f-42fe-a67e-9ac3ec2f4aed" />


## Current Status

The repository currently ships **Sprint 2 - Active Session Core**.

- Guide management is available in-app, with SwiftData-backed persistence and workspace import/export plumbing
- Session setup, active interview capture, live transcript display, question tracking, ad hoc notes, and session history are implemented
- Live transcription is powered by FluidAudio's `StreamingEouAsrManager`, with Sortformer-based diarization for provisional speaker labels and a Speech fallback path when FluidAudio is unavailable
- Finalized transcript turns, gaps, question statuses, and notes are persisted incrementally through SwiftData during the session
- Speaker labeling is still heuristic and not production-grade yet, and export generation remains Sprint 3 work

## AI Assistant Rules Files

This template includes **opinionated rules files** for popular AI coding assistants. These files establish coding standards, architectural patterns, and best practices for modern iOS development using the latest APIs and Swift features.

### Included Rules Files
- **Claude Code**: `CLAUDE.md` - Claude Code rules
- **Cursor**: `.cursor/*.mdc` - Cursor-specific rules
- **GitHub Copilot**: `.github/copilot-instructions.md` - GitHub Copilot rules

### Customization Options
These rules files are **starting points** - feel free to:
- ✅ **Edit them** to match your team's coding standards
- ✅ **Delete them** if you prefer different approaches
- ✅ **Add your own** rules for other AI tools
- ✅ **Update them** as new iOS APIs become available

### What Makes These Rules Opinionated
- **No ViewModels**: Embraces pure SwiftUI state management patterns
- **Swift 6+ Concurrency**: Enforces modern async/await over legacy patterns
- **Latest APIs**: Recommends iOS 18+ features with optional iOS 26 guidelines
- **Testing First**: Promotes Swift Testing framework over XCTest
- **Performance Focus**: Emphasizes @Observable over @Published for better performance

**Note for AI assistants**: You MUST read the relevant rules files before making changes to ensure consistency with project standards.

## Project Architecture

```
InterviewPartner/
├── Config/                                   # XCConfig, Info.plist, entitlements
├── InterviewPartner.xcworkspace/             # Open this file in Xcode
├── InterviewPartner.xcodeproj/               # App shell project
├── InterviewPartner/                         # App target wiring
│   ├── Assets.xcassets/                      # App-level assets (icons, colors)
│   ├── InterviewPartnerApp.swift             # App entry point
│   └── InterviewPartner.xctestplan           # Test configuration
├── Packages/
│   ├── InterviewPartnerDomain/               # Core models and repository protocols
│   ├── InterviewPartnerData/                 # SwiftData schema and repository implementations
│   ├── InterviewPartnerFeatures/             # SwiftUI feature surfaces and coordinators
│   └── InterviewPartnerServices/             # Environment, permissions, transcription, workspace services
├── InterviewPartnerPackage/                  # Legacy scaffold package; not the main implementation path
├── InterviewPartnerUITests/                  # UI automation tests
├── docs/                                     # PRD and supporting docs
└── rpi/                                      # Implementation plans and research notes
```

## Key Architecture Points

This is a modern iOS application using a **workspace + multiple SPM packages** architecture for clean separation between the app shell, domain contracts, persistence, features, and services. Built on top of [FluidAudio's](https://github.com/FluidInference/FluidAudio) great work.

### Package Responsibilities
- **App Shell**: `InterviewPartner/` contains the app target and injects the shared `AppEnvironment`
- **Domain**: `Packages/InterviewPartnerDomain/` defines guide/session models and repository protocols
- **Data**: `Packages/InterviewPartnerData/` owns the SwiftData schema plus guide/session repository implementations
- **Features**: `Packages/InterviewPartnerFeatures/` contains the tab root plus Sessions, Guides, Settings, and active-session UI flows
- **Services**: `Packages/InterviewPartnerServices/` wires the environment, permissions, workspace services, and transcription stack
- **Separation**: the app target stays thin while feature and persistence logic live in packages

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

## Development Notes

### Code Organization
Most development happens under `Packages/`:

- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/InterviewPartnerRootView.swift` wires the main tab UI
- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift` handles session history and new-session setup
- `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/ActiveSessionFeature.swift` drives the live interview experience
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift` contains the FluidAudio and Speech transcription integration
- `Packages/InterviewPartnerData/Sources/InterviewPartnerData/SwiftDataSessionRepository.swift` persists incremental session state

### Running the App
- Open `InterviewPartner.xcworkspace` in Xcode
- Run the `InterviewPartner` scheme
- The first run will request microphone access
- Create or import a workspace in Settings if needed, then create a guide in the Guides tab
- Start a session from the Sessions tab, choose a guide, and optionally set a participant label
- The first transcription start may download or load FluidAudio models into Application Support, so expect a longer startup
- If diarization or FluidAudio startup fails, the app can fall back to Speech-based transcription with reduced capability
- Pause briefly between sentences so the end-of-utterance detector can finalize a turn

### What Sprint 2 Proves Today
- Sessions can be created from a persisted guide and returned to history when finalized
- Live partial transcript updates and finalized utterance turns flow into the active-session UI
- Question coverage can be tracked in-session, including tap-to-cycle status changes and skip interactions
- Ad hoc notes and transcript gaps are persisted during capture
- Finalized turns are stored with speaker label, timing metadata, and attribution confidence
- Speaker labeling still needs refinement, and export generation is intentionally deferred to Sprint 3

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct NewView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit the specific package that owns the concern you are changing. For example, transcription and environment dependencies live in `Packages/InterviewPartnerServices/Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "InterviewPartnerServices",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Domain Tests**: `Packages/InterviewPartnerDomain/Tests/InterviewPartnerDomainTests/` (Swift Testing framework)
- **Data Tests**: `Packages/InterviewPartnerData/Tests/InterviewPartnerDataTests/` (Swift Testing framework)
- **UI Tests**: `InterviewPartnerUITests/` (XCUITest framework)
- **Test Plan**: `InterviewPartner.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### Entitlements Management
App capabilities are managed through a **declarative entitlements file**:
- `Config/InterviewPartner.entitlements` - All app entitlements and capabilities
- AI agents can safely edit this XML file to add HealthKit, CloudKit, Push Notifications, etc.
- No need to modify complex Xcode project files

### Asset Management
- **App-Level Assets**: `InterviewPartner/Assets.xcassets/` (app icon, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "InterviewPartnerFeatures",
    dependencies: [],
    resources: [.process("Resources")]
)
```

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.
