# Audio Quality & Diarization Improvement Plan

**Date:** 2026-03-23
**Author:** Claude Code
**Status:** Draft

## Problem Statement

### Issue 1: Real-World Audio Quality Degradation
When running the transcription app in the iOS Simulator and playing test audio through laptop speakers (which then gets captured by the microphone), transcription accuracy drops significantly compared to the benchmark results.

**Root Cause:**
- **Benchmark uses `FileAudioReplayer`** - feeds audio directly into the transcription pipeline
- **Real-world uses `MicrophoneAudioProvider`** - captures audio through the microphone
- The acoustic path (speaker → air → microphone) introduces:
  - Frequency response distortion (laptop speakers have limited bandwidth, typically 200Hz-16kHz)
  - Room reverberation and echo
  - Background noise
  - Volume/distance variations
  - Potential acoustic feedback/echo cancellation artifacts

**Impact:**
- WER (Word Error Rate) significantly higher in real-world conditions
- Users will experience worse performance than benchmark suggests
- Gap between "lab" and "field" performance undermines user trust

### Issue 2: Poor Speaker Diarization (60.64% Baseline)
The diarization accuracy is only 60.64%, meaning nearly 40% of words are misattributed to the wrong speaker.

**Root Cause:**
- Single turn detected in test case when there should be multiple
- All audio attributed to "Speaker A" despite ground truth having 2 distinct speakers
- The `DominantSpeakerMatcher` likely fails when:
  - Speaker segments overlap significantly
  - Turn boundaries don't align with diarization segments
  - Low confidence in speaker attribution (confidence threshold too aggressive)

---

## Phase 1: Audio Preprocessing Pipeline (Week 1-2)

### 1.1 Add Audio Enhancement Module

Create a new `AudioPreprocessor` that applies real-time audio enhancement before feeding to ASR and diarization.

```swift
// New file: InterviewPartnerServices/AudioPreprocessor.swift
public protocol AudioPreprocessor: Sendable {
    func process(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer
}

public struct AudioEnhancementPipeline: AudioPreprocessor {
    private let noiseSuppressor: NoiseSuppressor?
    private let automaticGainControl: AutomaticGainControl?
    private let voiceActivityDetector: VoiceActivityDetector?

    public func process(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Chain: AGC → Noise Suppression → VAD filtering
    }
}
```

**Components to implement:**

| Component | Purpose | Implementation Approach |
|-----------|---------|----------------------|
| `AutomaticGainControl` | Normalize volume levels | WebRTC AGC algorithm or custom RMS-based normalization |
| `NoiseSuppressor` | Remove background noise | WebRTC NS or Core ML-based noise suppression |
| `VoiceActivityDetector` | Filter non-speech frames | Energy-based + ML-based hybrid detection |
| `AcousticEchoCanceller` | Remove echo if speaker output present | WebRTC AEC or simple delay-line subtraction |

### 1.2 Integration Points

Modify `AudioTapBridge.makeHandler` to apply preprocessing:

```swift
nonisolated static func makeHandler(
    asrManager: StreamingEouAsrManager,
    diarizationEngine: LiveDiarizationEngine?,
    preprocessor: AudioPreprocessor? = nil  // NEW
) -> @Sendable (AVAudioPCMBuffer) -> Void {
    { buffer in
        let processedBuffer = preprocessor?.process(buffer) ?? buffer
        // ... rest of handler
    }
}
```

### 1.3 Implementation Priority

1. **RMS Normalization** (Quick win) - Scale audio to target dB level
2. **High-pass filter** (Quick win) - Remove low-frequency noise below 80Hz
3. **WebRTC Noise Suppression** (Medium effort) - Proven algorithm, can use existing Swift bindings
4. **Automatic Gain Control** (Medium effort) - Dynamic range compression

---

## Phase 2: Diarization Improvements (Week 2-3)

### 2.1 Investigate Current Diarization Behavior

**Action Items:**
1. Add detailed logging to `LiveDiarizationEngine` to capture:
   - Number of segments detected
   - Segment boundaries vs turn boundaries
   - Confidence scores per segment
   - Overlap between segments and turns

2. Create a diagnostic test that outputs:
   - Visual timeline of diarization segments vs turns
   - Confidence distribution
   - Misattributed segments

### 2.2 Improve Turn-Diarization Alignment

**Current Issue:** The `DominantSpeakerMatcher.attributeTurn` uses a simple overlap algorithm that fails when:
- Turn boundaries don't align with diarization segments
- Multiple speakers are active within a single turn window

**Solutions:**

#### Option A: Proportional Attribution (Recommended)
Instead of "winner takes all", attribute speaker based on proportional overlap:

```swift
static func attributeTurnProportional(
    segments: [DiarizedSegment],
    windowStart: TimeInterval,
    windowEnd: TimeInterval
) -> DiarizationAttribution {
    // Calculate overlap percentage for each speaker
    // Attribute to speaker with >60% overlap
    // Mark as "Mixed" if no speaker dominates
}
```

#### Option B: Segment-Level Reconciliation
Break turns at diarization segment boundaries:

```swift
// If a turn spans multiple speaker segments, split it
// Turn "A and B speaking" → Turn 1 "A speaking" + Turn 2 "B speaking"
```

#### Option C: Lower Confidence Thresholds
Current threshold (line 525 in TranscriptionServices.swift):
```swift
if dominantOverlap < 0.25 || (secondOverlap > 0 && dominantOverlap / secondOverlap < 1.25)
```

This is too aggressive. Consider:
- Lowering minimum overlap from 0.25 to 0.15
- Lowering dominance ratio from 1.25 to 1.1

### 2.3 Speaker Count Estimation

**Current:** Uses number of unique speaker indices from diarization
**Problem:** May over/under-estimate if diarization is noisy

**Improvement:** Add speaker count estimation heuristic:
- Analyze turn-taking patterns
- Check for overlapping speech
- Validate against expected speaker count from session metadata

---

## Phase 3: Real-World Testing Framework (Week 3-4)

### 3.1 Create "Acoustic Path" Benchmark

Add a new benchmark mode that simulates real-world conditions:

```swift
// In BenchmarkCLI, add new option:
// --acoustic-degrade LEVEL  # none, light, moderate, heavy

public struct AcousticDegrader: AudioPreprocessor {
    enum Level {
        case light      // Add 20dB SNR noise, slight reverb
        case moderate   // Add 10dB SNR noise, moderate reverb
        case heavy      // Add 5dB SNR noise, heavy reverb, frequency cutoff
    }

    func process(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Apply convolution reverb, add noise, frequency filtering
    }
}
```

### 3.2 Device-Specific Testing

Create a device-based test workflow:
1. Play test audio on Device A (at known volume)
2. Record on Device B (running InterviewPartner)
3. Compare transcription vs ground truth
4. Measure WER and diarization accuracy

### 3.3 Metrics Dashboard

Add to benchmark output:
- Signal-to-noise ratio estimation
- Speech percentage in audio
- Dynamic range
- Frequency spectrum analysis

---

## Phase 4: Model-Level Improvements (Week 4-6)

### 4.1 Fine-tune ASR on Noisy Audio

If using Parakeet EOU models:
- Fine-tune on audio with various noise levels
- Add data augmentation: noise injection, reverb simulation
- Target 16kHz sample rate (matches current pipeline)

### 4.2 Diarization Model Improvements

**Current:** Sortformer-based diarization
**Potential improvements:**
- Increase lookahead window for better context
- Adjust clustering thresholds based on observed speaker count
- Use voice embedding similarity for re-clustering

### 4.3 Adaptive Processing

Implement runtime adaptation:
- Estimate noise floor during silence
- Adjust preprocessing parameters dynamically
- Detect acoustic environment (quiet room, noisy cafe, etc.)

---

## Implementation Details

### Audio Preprocessor Implementation

```swift
// InterviewPartnerServices/AudioPreprocessor.swift
import Accelerate
import AVFoundation

public final class AudioPreprocessor: Sendable {
    private let targetRMS: Float
    private let noiseGateThreshold: Float
    private let highPassCutoff: Float

    public init(
        targetRMS: Float = 0.1,  // -20dB
        noiseGateThreshold: Float = 0.005,
        highPassCutoff: Float = 80.0  // Hz
    ) {
        self.targetRMS = targetRMS
        self.noiseGateThreshold = noiseGateThreshold
        self.highPassCutoff = highPassCutoff
    }

    public func process(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let data = buffer.floatChannelData else { return buffer }
        let frameLength = Int(buffer.frameLength)

        // 1. High-pass filter to remove low-frequency rumble
        applyHighPassFilter(data[0], frameCount: frameLength, cutoffHz: highPassCutoff, sampleRate: Float(buffer.format.sampleRate))

        // 2. Calculate RMS and apply gain normalization
        var rms: Float = 0
        vDSP_rmsqv(data[0], 1, &rms, vDSP_Length(frameLength))

        if rms > noiseGateThreshold {
            let gain = min(targetRMS / rms, 10.0)  // Cap gain at 20dB
            var scaledGain = gain
            vDSP_vsmul(data[0], 1, &scaledGain, data[0], 1, vDSP_Length(frameLength))
        }

        // 3. Soft limiting to prevent clipping
        applySoftLimit(data[0], frameCount: frameLength)

        return buffer
    }

    private func applyHighPassFilter(_ data: UnsafeMutablePointer<Float>, frameCount: Int, cutoffHz: Float, sampleRate: Float) {
        // Simple first-order high-pass filter: y[n] = x[n] - x[n-1] + α*y[n-1]
        // Where α = 1 - 2π*fc/fs
        let alpha = 1.0 - (2.0 * .pi * cutoffHz / sampleRate)
        var prevInput: Float = 0
        var prevOutput: Float = 0

        for i in 0..<frameCount {
            let input = data[i]
            let output = input - prevInput + alpha * prevOutput
            data[i] = output
            prevInput = input
            prevOutput = output
        }
    }

    private func applySoftLimit(_ data: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let sample = data[i]
            // Tanh-based soft limiter
            data[i] = tanh(sample * 1.5) / 1.5
        }
    }
}
```

### Diarization Logging

```swift
// Add to LiveDiarizationEngine
func logDiagnostics() {
    let snapshot = currentSnapshot()
    logger.info("""
    Diarization Diagnostics:
    - Total segments: \(snapshot.segments.count)
    - Unique speakers: \(snapshot.attributedSpeakerCount)
    - Audio duration: \(snapshot.totalAudioSeconds)s
    - Segments per second: \(Double(snapshot.segments.count) / snapshot.totalAudioSeconds)
    """)

    for segment in snapshot.segments.prefix(10) {
        logger.debug("Segment: Speaker \(segment.speakerIndex), \(segment.startTimeSeconds)s-\(segment.endTimeSeconds)s")
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
@Test func audioPreprocessorNormalizesVolume()
@Test func audioPreprocessorAppliesHighPassFilter()
@Test func dominantSpeakerMatcherHandlesTiedOverlap()
@Test func diarizationSplitsTurnsAtSegmentBoundaries()
```

### Integration Tests

1. **Benchmark with acoustic degradation**
   ```bash
   BenchmarkCLI --test-data tests/test-data --acoustic-degrade moderate
   ```

2. **Device recording test**
   - Play audio on Mac at 50% volume
   - Record on iPhone held at 1 foot distance
   - Measure WER vs direct file benchmark

3. **Speaker separation test**
   - Use 2-speaker audio with clear turn-taking
   - Verify diarization accuracy >80%
   - Verify speaker switches are detected

### Success Metrics

| Metric | Current | Phase 1 Target | Phase 2 Target | Final Target |
|--------|---------|---------------|----------------|--------------|
| WER (clean audio) | 17% | 15% | 15% | 12% |
| WER (moderate noise) | ~35% | 25% | 22% | 18% |
| Diarization Accuracy | 60.6% | 60.6% | 75% | 85% |
| Speaker Switch Detection | Poor | Poor | Good | Excellent |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| WebRTC integration complexity | Medium | Medium | Use simpler custom implementations first |
| Performance overhead | Medium | High | Profile on device, optimize hot paths |
| Over-processing artifacts | Medium | Medium | Add bypass mode, A/B testing |
| Diarization model limitations | High | High | Consider cloud-based diarization fallback |

---

## Next Steps

1. **Immediate (Today):**
   - Implement basic `AudioPreprocessor` with RMS normalization and high-pass filter
   - Add diagnostic logging to diarization engine

2. **This Week:**
   - Integrate preprocessor into audio pipeline
   - Run degraded benchmark to establish new baseline
   - Analyze diarization segment/turn alignment

3. **Next Week:**
   - Implement proportional speaker attribution
   - Add noise suppression
   - Device testing with real acoustic path

---

## Related Resources

- [WebRTC Audio Processing](https://webrtc.org/documentation/)
- [Sortformer Diarization Paper](https://arxiv.org/abs/2310.04972)
- [Parakeet EOU Documentation](https://huggingface.co/nvidia/parakeet-eou-0.6b-v2)
- Previous Plan: [Mobile Transcription EOU and Diarization Plan](./2026-03-19-13-14_mobile_transcription_eou_diarization_plan.md)
