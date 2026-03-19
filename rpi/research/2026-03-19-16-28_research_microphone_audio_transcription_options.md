---
date: 2026-03-19T16:28:07-07:00
researcher: Jason Wu / Codex
topic: "Options to improve transcription when the root cause is poor microphone audio"
tags: [research, mobile, transcription, microphone, audio-quality, ios, fluidaudio]
status: complete
---

# Research: Options to improve transcription when the root cause is poor microphone audio

## Research Question
Use the codebase plus web research to identify the best options to improve voice-to-text transcription if the main root cause is poor quality audio coming from the microphone. Order the options by lowest risk / highest value, with emphasis on options that do not require major refactoring.

## Summary
Yes: there are several high-value options that do not require a major refactor.

The key repo fact is that microphone capture is centralized in one place. `DefaultTranscriptionService` configures a minimal `AVAudioSession` and installs a single `AVAudioEngine` tap, then hands that audio to FluidAudio (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:286`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:294`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:300`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:803`). That means the best first improvements are capture-layer and routing changes, not ASR rewrites.

Ordered by lowest engineering risk / highest likely value:

1. Pin the input route and built-in microphone intentionally; stop passively accepting whatever input the system picks.
2. Add route-quality guardrails and a short preflight check so the app warns about obviously bad capture conditions before transcription starts.
3. Support better microphones explicitly: wired / USB audio interfaces now, newer high-quality AirPods paths later.
4. Add directional built-in mic selection profiles (`front` / `back` / `bottom`, polar pattern where available) and benchmark them for interview placements.
5. Expose or adopt Apple microphone modes where the OS supports them, especially Voice Isolation for recording on newer iOS.
6. Only after that, consider heavier changes: AVAudioEngine voice-processing mode, denoising DSP, or ASR pipeline/model changes.

The strongest immediate recommendation is option 1. The current app always allows Bluetooth HFP and does not choose a preferred input or built-in mic data source (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:289`). Apple’s routing docs say selecting a Bluetooth HFP input also moves output to Bluetooth HFP, and Apple’s newer recording APIs explicitly describe HFP as the fallback when high-quality Bluetooth recording is unavailable, which is a strong signal that the current path can land on a lower-quality capture route for speech transcription rather than the best built-in mic path (`https://developer.apple.com/library/archive/qa/qa1799/_index.html`, `https://developer.apple.com/videos/play/wwdc2025/251/`).

## Detailed Findings

### 1. Current repo architecture makes capture fixes unusually cheap
- The app uses one `AVAudioEngine` input tap and one `configureAudioSession()` function for the live path, so microphone-routing changes are localized (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:286`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:294`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:300`).
- That session config is currently minimal: category `.record`, mode `.default`, option `.allowBluetoothHFP`, then `setActive(true)` (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:286`).
- There is no repo evidence of preferred-input selection, preferred data-source selection, microphone-profile UI, or route diagnostics beyond permission handling; the transcription service is effectively trusting the default route.

Why this matters:
- If the main failure mode is poor capture quality, the app is attacking the problem too late. It currently accepts the incoming route and only tries to recover later in transcription.
- Because capture setup is localized, several fixes are small-scope changes in one service instead of cross-cutting refactors.

### 2. Best first move: explicitly choose the microphone path and avoid accidental low-quality routes
- Apple’s audio-session hardware guide says that on devices with multiple built-in microphones, the chosen mode affects DSP and routing, and developers can explicitly set a preferred input, data source, and even polar pattern after configuring and activating the session (`https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/OptimizingForDeviceHardware/OptimizingForDeviceHardware.html`).
- Apple QA1799 is more concrete:
  - modes can change which built-in microphone is used
  - `videoRecording` can select different microphones and beamforming behavior
  - developers can set `preferredInput`, `preferredDataSource`, and `preferredPolarPattern`
  - selecting Bluetooth HFP as preferred input automatically changes output to Bluetooth HFP (`https://developer.apple.com/library/archive/qa/qa1799/_index.html`).
- The current app always enables `.allowBluetoothHFP` and never overrides the system’s choice (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:289`).
- Inference from Apple’s newer recording guidance:
  - WWDC25 introduces `bluetoothHighQualityRecording` and says Bluetooth HFP is the fallback when high-quality recording is unavailable (`https://developer.apple.com/videos/play/wwdc2025/251/`).
  - That strongly suggests the current HFP-allowed path is not the route you want to drift onto by default for interview transcription.

Recommendation:
- Default to the built-in microphone unless the user explicitly opts into another input.
- Add a small route policy:
  - if current input is Bluetooth HFP, warn the user and offer “Use iPhone Mic” / “Keep Bluetooth Mic”
  - if a built-in mic is available, call `setPreferredInput(builtInMic)`
  - benchmark preferred data sources for the most common interview placements
- This is a small change in `configureAudioSession()` plus a small UX surface, not a pipeline rewrite.

Risk / value / refactor:
- Risk: low
- Value: high
- Refactor size: small

### 3. Add a short capture preflight and route diagnostics before starting transcription
- Apple’s support guidance for unclear microphone audio is operational but useful: remove obstructive cases or films, clear debris, verify the app has microphone access, and test the relevant microphone positions (`https://support.apple.com/en-us/101600`).
- Voice Memos also explicitly tells users to change recording level by moving the microphone closer to or farther from the source (`https://support.apple.com/en-afri/guide/iphone/-iph4d2a39a3b/ios`).
- The app currently has permission recovery, but not capture-quality recovery or route explanation (`README.md:29`, `Packages/InterviewPartnerFeatures/Sources/InterviewPartnerFeatures/SessionListFeature.swift:411`).

Recommendation:
- Before `start()`, surface a lightweight “capture check”:
  - current input route name
  - whether the app is using built-in mic vs Bluetooth HFP vs headset mic
  - a short warning if Bluetooth HFP is active
  - a short prompt for common failure causes: case/debris, device placement, distance
- Optional small metric layer:
  - show RMS/clipping level from the tap for 2 to 3 seconds
  - if sustained level is too low or clipping is high, warn before the interview starts

Why this is worth doing:
- It will not improve the waveform by itself, but it prevents bad sessions from starting on obviously poor capture.
- Engineering cost is low because the tap already exists and the relevant state lives in one service.

Risk / value / refactor:
- Risk: low
- Value: medium to high
- Refactor size: small

### 4. Explicit support for better hardware is zero-to-small engineering work and high real-world value
- Apple’s Voice Memos guide says iPhone can record with the built-in microphone, a supported headset, or an external microphone, and that you can use an external stereo microphone or audio interface that works with iPhone (`https://support.apple.com/en-afri/guide/iphone/-iph4d2a39a3b/ios`).
- The repo already uses `AVAudioSession`; there is no architectural blocker to selecting a wired or USB input once routed correctly.
- For users who truly have poor built-in microphone results because of placement or environment, better hardware is often a larger gain than changing ASR models.

Recommendation:
- Short term:
  - officially support wired / USB microphones and audio interfaces
  - explain in-app which route is active
  - keep built-in mic as the default fallback
- Later:
  - on newer OS versions, consider Apple’s input-picker path so the user can switch inputs from inside the app (`https://developer.apple.com/videos/play/wwdc2025/251/`).

Risk / value / refactor:
- Risk: low
- Value: high
- Refactor size: none to small

### 5. Directional mic profiles are likely the best no-refactor acoustic improvement on built-in hardware
- Apple’s docs say session modes affect built-in microphone selection and DSP, and the app can explicitly choose built-in mic data sources and, on supported devices, polar patterns like cardioid (`https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/OptimizingForDeviceHardware/OptimizingForDeviceHardware.html`, `https://developer.apple.com/library/archive/qa/qa1799/_index.html`).
- Apple explicitly calls out `AVAudioSessionModeVideoRecording` selecting non-default microphones and beamforming on supported hardware (`https://developer.apple.com/library/archive/qa/qa1799/_index.html`).
- The current app uses `.default` mode only (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:289`).

Recommendation:
- Add device-placement profiles, then benchmark them on real interview setups:
  - `table_between_people`: built-in mic + default mode
  - `phone_facing_participant`: built-in front/back mic + `videoRecording`
  - `self_capture_close_range`: built-in bottom/front mic + cardioid if available
- Do not ship one “smart” mic choice blindly.
- Treat this as an A/B matrix against real recordings, because directional gain can help one speaker while hurting another if the phone placement is wrong.

Risk / value / refactor:
- Risk: low to medium
- Value: medium to high
- Refactor size: small

### 6. Apple microphone modes are promising, but the recording-app story is OS-version dependent
- Apple Support says Voice Isolation, Wide Spectrum, and Automatic Mic Mode can be chosen per app, and that recording-app Voice Isolation requires iOS 26 or later; Automatic Mic Mode requires iOS 18 or later (`https://support.apple.com/en-us/101993`).
- Apple also documents `NSAlwaysAllowMicrophoneModeControl`, which lets someone configure microphone mode before the microphone is active (`https://developer.apple.com/documentation/bundleresources/information-property-list/nsalwaysallowmicrophonemodecontrol`).
- The repo currently targets iOS 18 (`Packages/InterviewPartnerServices/Package.swift:8`), so recording-app Voice Isolation is not a universal baseline today.

Recommendation:
- Near term:
  - do not rely on Voice Isolation as the main fix for the current iOS 18 floor
  - if helpful, allow Automatic / Standard control where the OS supports it
- Medium term:
  - if the product later raises its floor or adds conditional iOS 26 behavior, expose microphone mode controls explicitly

Risk / value / refactor:
- Risk: low
- Value: medium
- Refactor size: small

### 7. New high-quality AirPods support is interesting, but it is a future-facing branch, not the first fix
- WWDC25 says iOS 26 introduces `bluetoothHighQualityRecording`, and if the app already uses `allowBluetoothHFP`, adding the new option makes high-quality recording the default while HFP remains fallback (`https://developer.apple.com/videos/play/wwdc2025/251/`).
- That is attractive because the current code already opts into HFP (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:289`).
- However, it is only helpful on newer OS/device combinations and only for users who actually want AirPods capture.

Recommendation:
- Keep this behind the main built-in-mic work.
- If you add it later:
  - prefer `bluetoothHighQualityRecording` where supported
  - keep clear route UI so the user knows whether they are on built-in mic, HQ AirPods, or fallback HFP

Risk / value / refactor:
- Risk: low to medium
- Value: medium
- Refactor size: small

### 8. AVAudioEngine voice-processing mode is plausible, but it is the first option that changes the session shape materially
- Apple’s AVAudioEngine update introduced voice-processing mode for echo cancellation / voice-over-IP scenarios. Apple says enabling it applies extra signal processing to input audio and requires both input and output nodes to be in voice-processing mode; it also cannot be enabled dynamically while the engine is running (`https://developer.apple.com/videos/play/wwdc2019/510/`).
- Apple’s category/mode matrix shows `voiceChat` is compatible with `playAndRecord`, not plain `record` (`https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionCategoriesandModes/AudioSessionCategoriesandModes.html`).
- The current app is input-only `.record` and does not use output-side audio nodes (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:286`, `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:311`).

Implication:
- This is not a major rewrite, but it is no longer just “change one route setting.”
- It changes category/mode assumptions and may affect routing and behavior in ways the current app does not need today.

Recommendation:
- Treat voice processing as an A/B experiment only if the actual problem is:
  - far-field speech
  - room echo
  - device speaker bleed
- Do not jump to this before trying input-route and mic-selection fixes.

Risk / value / refactor:
- Risk: medium
- Value: medium
- Refactor size: medium

### 9. Denoising DSP and ASR changes are later moves, not first moves
- FluidAudio already normalizes audio with `AudioConverter`, and its docs emphasize correct format conversion to 16 kHz mono Float32 rather than custom byte parsing (`Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:603`, `.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Documentation/ASR/GettingStarted.md:50`).
- The repo also already has access to FluidAudio streaming VAD and a richer lower-level streaming ASR surface if the team later wants more capture-aware transcription logic (`.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:10`, `.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift:746`).
- But if the true issue is poor microphone signal quality, adding denoisers or swapping ASR surfaces is treating downstream symptoms.

Recommendation:
- Only consider these after capture-layer fixes are benchmarked:
  - add denoising / WebRTC-style preprocessing
  - add recorded-audio benchmarking fixtures
  - replace the EOU surface with lower-level token-timed streaming ASR
  - change models or add cloud fallback

Risk / value / refactor:
- Risk: medium to high
- Value: variable
- Refactor size: medium to major

## Code References
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:286` - current audio session setup is `.record` + `.default` + `.allowBluetoothHFP`.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:294` - audio capture starts from one `AVAudioEngine` input tap.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:300` - the input tap is installed directly on the input node.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:603` - diarization path resamples incoming buffers through FluidAudio `AudioConverter`.
- `Packages/InterviewPartnerServices/Sources/InterviewPartnerServices/TranscriptionServices.swift:803` - live audio tap feeds ASR and diarization directly.
- `Packages/InterviewPartnerServices/Package.swift:8` - iOS deployment target is 18.
- `README.md:24` - live transcription uses FluidAudio `StreamingEouAsrManager`.
- `README.md:29` - current UX already handles microphone permission denial, but not capture-quality diagnosis.
- `.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Documentation/ASR/GettingStarted.md:50` - FluidAudio expects normalized 16 kHz mono audio via `AudioConverter`.
- `.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:10` - upstream VAD supports streaming start/end events.
- `.build/xcodebuildmcp-derived/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift:746` - lower-level streaming ASR exposes confirmed/volatile updates and token timings.

## Architecture Insights
- The app’s capture layer is the best leverage point because it is centralized and thin.
- The current implementation does not have a microphone-routing abstraction yet, but it does not need one to get the first wins; a small route-policy layer inside `DefaultTranscriptionService` is enough.
- If microphone quality is truly the root cause, the best sequence is:
  1. improve route and microphone choice
  2. improve capture observability
  3. add optional system capture enhancements
  4. only then revisit transcription internals

## Open Questions
- What is the dominant real-world setup:
  - phone on table between two people
  - phone pointed at the participant
  - interviewer holding the phone close
  - AirPods / headset capture
- How often are users actually landing on Bluetooth HFP today?
- Is the main failure environmental noise, far-field distance, echo, clipping, or simply the wrong microphone route?
- Does the product want to stay iOS 18-first, or is conditional iOS 26 behavior acceptable for microphone-mode and high-quality Bluetooth features?

## Recommended Next Moves
1. Change the default policy so the app prefers the built-in microphone and does not silently drift onto Bluetooth HFP unless the user explicitly chooses it.
2. Add route labeling and a 2 to 3 second capture preflight before transcription starts.
3. Add one or two built-in mic profiles and benchmark them on real interview placements:
   - default built-in mic
   - directional/video-recording profile
4. If poor capture still dominates, support better external microphones explicitly and show the active route in-app.
5. Defer voice-processing mode, denoising DSP, and ASR-surface refactors until after those simpler capture-layer changes are measured.
