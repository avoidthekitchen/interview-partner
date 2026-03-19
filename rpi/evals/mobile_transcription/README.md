# Mobile Transcription Eval

This directory stores the checked-in replay benchmark artifacts for the mobile transcription pipeline.

## Commands

Phase 1 baseline:

```bash
swift run --package-path Packages/InterviewPartnerServices InterviewPartnerTranscriptionEvalCLI --fixture-set baseline --variant phase1_baseline --output rpi/evals/mobile_transcription/baseline_metrics.json
```

Current production path:

```bash
swift run --package-path Packages/InterviewPartnerServices InterviewPartnerTranscriptionEvalCLI --fixture-set baseline --variant production_current --output rpi/evals/mobile_transcription/latest.json --compare-baseline /absolute/path/to/rpi/evals/mobile_transcription/baseline_metrics.json
```

Pinned tuned comparison:

```bash
swift run --package-path Packages/InterviewPartnerServices InterviewPartnerTranscriptionEvalCLI --fixture-set baseline --variant pinned_tuned --output rpi/evals/mobile_transcription/variant_results/pinned_tuned.json --compare-baseline /absolute/path/to/rpi/evals/mobile_transcription/latest.json
```

Local audio integration benchmark:

```bash
mkdir -p rpi/evals/mobile_transcription/local_fixtures
mkdir -p rpi/evals/mobile_transcription/local_reports

# Copy the tracked template and add a short approved excerpt plus aligned turn timings.
cp rpi/evals/mobile_transcription/local_audio_integration_fixture.template.json \
  rpi/evals/mobile_transcription/local_fixtures/local_excerpt_sample.json

swift run --package-path Packages/InterviewPartnerServices InterviewPartnerTranscriptionEvalCLI \
  --mode audio-integration \
  --fixtures-root /absolute/path/to/rpi/evals/mobile_transcription/local_fixtures \
  --fixture-set local_audio \
  --variant production_current \
  --output /absolute/path/to/rpi/evals/mobile_transcription/local_reports/local_audio_report.json
```

## Current Read

- `baseline_metrics.json` is the stable Phase 1 baseline envelope for no-regression checks.
- `latest.json` is the current production-path replay report.
- `latest.comparison.json` shows where the current path improved or regressed versus the Phase 1 baseline.
- `variant_results/pinned_tuned.json` is the tuned pinned-config replay report.
- `variant_results/pinned_tuned.comparison.json` compares the tuned pinned config against the current production path.
- `variant_results/recommended_production_config.json` records the current tuning decision artifact.

## Current Benchmark Notes

- The VAD-grounded path removed turn-boundary MAE regressions across the checked-in fixture corpus.
- The offline diarization pass improved `final_speaker_accuracy` on the short-ack fixture.
- The offline pass introduces non-zero `offline_runtime_rtf`; that cost is now treated as an explicit benchmark gate instead of an accidental regression.
- The checked-in recommendation remains `production_current`; the pinned tuned replay variant was neutral on the current corpus.

## Local Audio Workflow

- `--fixtures-root` lets the CLI load fixtures from any local directory instead of the checked-in package resources.
- `--mode audio-integration` runs the actual ASR/VAD/live-diarization/offline-reconciliation path on the referenced audio file.
- `rpi/evals/mobile_transcription/local_fixtures/` and `rpi/evals/mobile_transcription/local_reports/` are git-ignored for local-only media and reports.
- Keep third-party audio and transcripts out of git unless you have explicit rights to redistribute them.
- Start with a short excerpt, accurate speaker labels, and approximate start/end timings; the integration report will tell you whether the system collapses turn count, session coverage, or speaker cardinality.
