## Summary

Used the approved local podcast assets:

- Audio: `/Users/mistercheese/Downloads/He_Yelled_N----er_At_Two_Black_Oscar_Nominees,_No_Apology_Needed_We_Beg_To_Diffe.mp3`
- Transcript: `/Users/mistercheese/Downloads/He_Yelled_N----er_At_Two_Black_Oscar_Nominees,_No_Apology_Needed_We_Beg_To_Diffe_transcription.txt`

The real-audio integration benchmark now records fixture failures instead of aborting the CLI when the audio path throws `Foundation._GenericObjCError.nilError`.

## Local Excerpt Used

Dense excerpt selected from the approved transcript:

- Window: `00:18:49-00:19:41`
- Relative duration: `52s`
- Expected turns: `7`
- Expected speakers: `3`

This excerpt was chosen because it has enough turn density to catch "only a few turns" and "single-speaker collapse" failures without relying on a long monologue window.

The local-only fixture and reports are gitignored under:

- `rpi/evals/mobile_transcription/local_fixtures/`
- `rpi/evals/mobile_transcription/local_reports/`

## Result

Both `phase1_baseline_audio_integration` and `production_current_audio_integration` failed on the approved excerpt before producing any transcript output.

Observed report shape:

- `actual_live_turn_count = 0`
- `actual_final_turn_count = 0`
- `expected_turn_recall = 0`
- `session_coverage_ratio = 0`
- `actual_live_speaker_count = 0`
- `actual_final_speaker_count = 0`
- notes include `Runner error: nilError`

The comparison report therefore shows no before/after delta on this excerpt. That is still useful: the automated eval now exposes the live audio path as failing outright on real third-party audio instead of silently looking healthy because the CLI crashed before producing metrics.

## Implication

The replay benchmark improvements are still useful for synthetic turn-boundary and speaker-cardinality checks, but the real-audio integration benchmark reveals a higher-priority issue:

- the current live audio path is not yet reliable on this approved real-world excerpt
- the failure happens in both baseline and current variants, so it is not evidence that the recent VAD/offline diarization changes caused it
- the next debugging target should be the underlying `nilError` in the audio-driven ASR path, not the replay metrics layer
