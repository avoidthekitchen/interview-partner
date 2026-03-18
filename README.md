# InterviewPartner - iOS App

## Background

There are a thousand user interview apps, but this one is mine. This app is intended to be a personal user interview companion for note-taking and in-conversation guidance — built around a loose script that keeps you on track without getting in your way. It has just enough structure to be useful and just enough flexibility to follow conversations wherever they organically go. I also want it to scale: as I bring more engineers from my team into the interview process, it should make it easy to share notes, synthesize findings, and surface insights across the team.

- Live voice-to-text transcription with speaker diarization, automatically distinguishing interviewer from interviewee
- On-device transcription for privacy and reliability in low-connectivity environments
- A loose interview script with key questions to answer, with live tracking so you always know which questions you've covered during a timeboxed conversation
- Optional LLM integration (OpenAI, Anthropic, etc.) to passively monitor the transcript, score question coverage in real time (1–10), and generate a findings summary after the interview wraps
- iOS and macOS first

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
├── InterviewPartner.xcworkspace/              # Open this file in Xcode
├── InterviewPartner.xcodeproj/                # App shell project
├── InterviewPartner/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── InterviewPartnerApp.swift              # App entry point
│   └── InterviewPartner.xctestplan            # Test configuration
├── InterviewPartnerPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/InterviewPartnerFeature/       # Your feature code
│   └── Tests/InterviewPartnerFeatureTests/    # Unit tests
└── InterviewPartnerUITests/                   # UI automation tests
```

## Key Architecture Points

This is a modern iOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code. Built on top of [FluidAudio's](https://github.com/FluidInference/FluidAudio) great work! 

### Workspace + SPM Structure
- **App Shell**: `InterviewPartner/` contains minimal app lifecycle code
- **Feature Code**: `InterviewPartnerPackage/Sources/InterviewPartnerFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

## Development Notes

### Code Organization
Most development happens in `InterviewPartnerPackage/Sources/InterviewPartnerFeature/` - organize your code as you prefer.

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
Edit `InterviewPartnerPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "InterviewPartnerFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `InterviewPartnerPackage/Tests/InterviewPartnerFeatureTests/` (Swift Testing framework)
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
    name: "InterviewPartnerFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.
