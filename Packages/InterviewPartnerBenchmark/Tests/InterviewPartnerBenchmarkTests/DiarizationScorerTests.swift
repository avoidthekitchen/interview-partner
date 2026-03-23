import Testing
@testable import InterviewPartnerBenchmark

@Suite("DiarizationScorer")
struct DiarizationScorerTests {

    // MARK: - Cycle 1: Perfect match

    @Test("Perfect 2-speaker transcript returns 100% accuracy")
    func perfectTwoSpeakerTranscript() {
        let reference: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker1"),
            LabeledWord(word: "world", speaker: "Speaker1"),
            LabeledWord(word: "how", speaker: "Speaker2"),
            LabeledWord(word: "are", speaker: "Speaker2"),
            LabeledWord(word: "you", speaker: "Speaker2"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "A"),
            LabeledWord(word: "world", speaker: "A"),
            LabeledWord(word: "how", speaker: "B"),
            LabeledWord(word: "are", speaker: "B"),
            LabeledWord(word: "you", speaker: "B"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 5)
        #expect(result.totalMatchedWords == 5)
    }

    // MARK: - Cycle 2: Zero accuracy (one side empty)

    @Test("Reference has words but hypothesis is empty returns 0% accuracy")
    func referenceNonEmptyHypothesisEmpty() {
        let reference: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker1"),
            LabeledWord(word: "world", speaker: "Speaker2"),
        ]
        let hypothesis: [LabeledWord] = []

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 0.0)
        #expect(result.correctWords == 0)
        #expect(result.totalMatchedWords == 0)
    }

    @Test("Hypothesis has words but reference is empty returns 0% accuracy")
    func hypothesisNonEmptyReferenceEmpty() {
        let reference: [LabeledWord] = []
        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "A"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 0.0)
        #expect(result.correctWords == 0)
        #expect(result.totalMatchedWords == 0)
    }

    // MARK: - Cycle 3: Partial misattribution

    @Test("Partial speaker misattribution returns expected percentage")
    func partialMisattribution() {
        // Reference: Speaker1 says "the cat sat", Speaker2 says "on the mat"
        let reference: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "Speaker1"),
            LabeledWord(word: "cat", speaker: "Speaker1"),
            LabeledWord(word: "sat", speaker: "Speaker1"),
            LabeledWord(word: "on", speaker: "Speaker2"),
            LabeledWord(word: "the", speaker: "Speaker2"),
            LabeledWord(word: "mat", speaker: "Speaker2"),
        ]

        // Hypothesis: A says first 4 words, B says last 2
        // After mapping: A→Speaker1, B→Speaker2
        // Words 1-3: A→Speaker1 vs Speaker1 ✓ (3 correct)
        // Word 4 "on": A→Speaker1 vs Speaker2 ✗
        // Word 5 "the": B→Speaker2 vs Speaker2 ✓
        // Word 6 "mat": B→Speaker2 vs Speaker2 ✓
        // Total: 5 correct out of 6 = 83.33...%
        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "A"),
            LabeledWord(word: "cat", speaker: "A"),
            LabeledWord(word: "sat", speaker: "A"),
            LabeledWord(word: "on", speaker: "A"),
            LabeledWord(word: "the", speaker: "B"),
            LabeledWord(word: "mat", speaker: "B"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        let expectedAccuracy = (5.0 / 6.0) * 100.0
        #expect(abs(result.accuracy - expectedAccuracy) < 0.01)
        #expect(result.correctWords == 5)
        #expect(result.totalMatchedWords == 6)
    }

    // MARK: - Cycle 4: Single speaker

    @Test("Single speaker input all correct returns 100% accuracy")
    func singleSpeakerCorrect() {
        let reference: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker1"),
            LabeledWord(word: "world", speaker: "Speaker1"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "X"),
            LabeledWord(word: "world", speaker: "X"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 2)
        #expect(result.totalMatchedWords == 2)
    }

    @Test("Single speaker in reference but two speakers in hypothesis reduces accuracy")
    func singleRefSpeakerTwoHypSpeakers() {
        // Reference: all Speaker1
        // Hypothesis: first word A, second word B
        // Mapping: A→Speaker1
        // B is new and Speaker1 already mapped, no more ref speakers → B maps to nothing
        // Word 1: A→Speaker1 vs Speaker1 ✓
        // Word 2: B→nil vs Speaker1 ✗
        // 1/2 = 50%
        let reference: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker1"),
            LabeledWord(word: "world", speaker: "Speaker1"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "A"),
            LabeledWord(word: "world", speaker: "B"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 50.0)
        #expect(result.correctWords == 1)
        #expect(result.totalMatchedWords == 2)
    }

    // MARK: - Cycle 5: Mismatched word counts (transcription errors)

    @Test("Hypothesis has extra words that get treated as insertions")
    func hypothesisExtraWords() {
        // Reference: "the cat"
        // Hypothesis: "the big cat"
        // Alignment: the=the, ins(big), cat=cat
        // Matched pairs: 2 (the, cat). Insertions don't count.
        // Speaker check: both correct → 100%
        let reference: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "S1"),
            LabeledWord(word: "cat", speaker: "S1"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "A"),
            LabeledWord(word: "big", speaker: "A"),
            LabeledWord(word: "cat", speaker: "A"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 2)
        #expect(result.totalMatchedWords == 2)
    }

    @Test("Hypothesis has missing words that get treated as deletions")
    func hypothesisMissingWords() {
        // Reference: "the big cat"
        // Hypothesis: "the cat"
        // Alignment: the=the, del(big), cat=cat
        // Matched pairs: 2. Deletions don't count.
        // Both correct → 100%
        let reference: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "S1"),
            LabeledWord(word: "big", speaker: "S1"),
            LabeledWord(word: "cat", speaker: "S1"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "A"),
            LabeledWord(word: "cat", speaker: "A"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 2)
        #expect(result.totalMatchedWords == 2)
    }

    @Test("Substituted words still check speaker labels")
    func substitutedWordsCheckSpeaker() {
        // Reference: "the cat sat" (S1, S1, S2)
        // Hypothesis: "the bat mat" (A, A, B)
        // Alignment: the=the, cat/bat=sub, sat/mat=sub
        // All 3 are matched. Mapping: A→S1, B→S2
        // the: A→S1 vs S1 ✓, bat: A→S1 vs S1 ✓, mat: B→S2 vs S2 ✓
        // 3/3 = 100%
        let reference: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "S1"),
            LabeledWord(word: "cat", speaker: "S1"),
            LabeledWord(word: "sat", speaker: "S2"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "the", speaker: "A"),
            LabeledWord(word: "bat", speaker: "A"),
            LabeledWord(word: "mat", speaker: "B"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 3)
        #expect(result.totalMatchedWords == 3)
    }

    // MARK: - Cycle 6: Sequential label mapping

    @Test("Sequential label mapping maps first hypothesis speaker to first reference speaker")
    func sequentialLabelMapping() {
        // Reference speakers appear in order: S1, S2, S3
        // Hypothesis speakers appear in order: X, Y, Z
        // Sequential mapping: X→S1, Y→S2, Z→S3
        let reference: [LabeledWord] = [
            LabeledWord(word: "alpha", speaker: "S1"),
            LabeledWord(word: "beta", speaker: "S2"),
            LabeledWord(word: "gamma", speaker: "S3"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "alpha", speaker: "X"),
            LabeledWord(word: "beta", speaker: "Y"),
            LabeledWord(word: "gamma", speaker: "Z"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 3)
        #expect(result.totalMatchedWords == 3)
    }

    @Test("Swapped hypothesis speaker labels still produce 100% via sequential mapping")
    func swappedLabelsSequentialMapping() {
        // Reference: S1 says "hello world", S2 says "good morning"
        // Hypothesis uses reversed label names but same structure
        // Sequential mapping adapts: first hyp speaker → first ref speaker
        let reference: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker1"),
            LabeledWord(word: "world", speaker: "Speaker1"),
            LabeledWord(word: "good", speaker: "Speaker2"),
            LabeledWord(word: "morning", speaker: "Speaker2"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "Speaker2"),
            LabeledWord(word: "world", speaker: "Speaker2"),
            LabeledWord(word: "good", speaker: "Speaker1"),
            LabeledWord(word: "morning", speaker: "Speaker1"),
        ]

        // Mapping: hyp "Speaker2" → ref "Speaker1" (first pair)
        //          hyp "Speaker1" → ref "Speaker2" (second pair)
        // All 4 words correct after mapping → 100%
        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 4)
        #expect(result.totalMatchedWords == 4)
    }

    // MARK: - Cycle 7: Edge cases

    @Test("Both empty returns 100% accuracy")
    func bothEmpty() {
        let result = DiarizationScorer.score(reference: [], hypothesis: [])

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 0)
        #expect(result.totalMatchedWords == 0)
    }

    @Test("Case insensitive word matching")
    func caseInsensitiveWordMatching() {
        let reference: [LabeledWord] = [
            LabeledWord(word: "Hello", speaker: "S1"),
            LabeledWord(word: "WORLD", speaker: "S1"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "hello", speaker: "A"),
            LabeledWord(word: "world", speaker: "A"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 100.0)
        #expect(result.correctWords == 2)
        #expect(result.totalMatchedWords == 2)
    }

    @Test("Three-speaker cyclic mismatch produces expected accuracy")
    func threeSpeakerCyclicMismatch() {
        // Reference: S1, S2, S3
        // Hypothesis: A, B, C but shifted by one position
        // A says word belonging to S1, B says word belonging to S2, C says word belonging to S3
        // BUT hypothesis attributes: word1→A, word2→C, word3→B (shifted)
        // Mapping: A→S1 (first pair: word1 A, ref S1)
        //          C→S2 (second pair: word2 C, ref S2)
        //          B→S3 (third pair: word3 B, ref S3)
        // Check: word1 A→S1 vs S1 ✓, word2 C→S2 vs S2 ✓, word3 B→S3 vs S3 ✓
        // All correct because mapping adapts. Let's make it actually mismatch:
        //
        // Make a scenario where mapping CAN'T fix it:
        // Ref: [a:S1, b:S1, c:S2, d:S2, e:S3, f:S3]
        // Hyp: [a:X,  b:Y,  c:X,  d:Z,  e:Y,  f:Z]
        // Mapping: X→S1 (first pair a)
        //          Y→S1 already taken... Y→?? first unused ref speaker from encounter
        // Actually Y's first encounter is b, ref speaker S1 which is taken. Y has no mapping.
        // Let me re-examine my implementation...
        //
        // The mapping code only maps when BOTH hyp speaker is unmapped AND ref speaker is unmapped.
        // So: a: X new, S1 new → X→S1
        //     b: Y new, S1 taken → skip
        //     c: X taken → skip
        //     d: Z new, S2 new → Z→S2
        //     e: Y new (still), S3 new → Y→S3
        //     f: Z taken → skip
        // Map: X→S1, Z→S2, Y→S3
        // Check: a X→S1 vs S1 ✓, b Y→S3 vs S1 ✗, c X→S1 vs S2 ✗,
        //        d Z→S2 vs S2 ✓, e Y→S3 vs S3 ✓, f Z→S2 vs S3 ✗
        // 3/6 = 50%
        let reference: [LabeledWord] = [
            LabeledWord(word: "a", speaker: "S1"),
            LabeledWord(word: "b", speaker: "S1"),
            LabeledWord(word: "c", speaker: "S2"),
            LabeledWord(word: "d", speaker: "S2"),
            LabeledWord(word: "e", speaker: "S3"),
            LabeledWord(word: "f", speaker: "S3"),
        ]

        let hypothesis: [LabeledWord] = [
            LabeledWord(word: "a", speaker: "X"),
            LabeledWord(word: "b", speaker: "Y"),
            LabeledWord(word: "c", speaker: "X"),
            LabeledWord(word: "d", speaker: "Z"),
            LabeledWord(word: "e", speaker: "Y"),
            LabeledWord(word: "f", speaker: "Z"),
        ]

        let result = DiarizationScorer.score(reference: reference, hypothesis: hypothesis)

        #expect(result.accuracy == 50.0)
        #expect(result.correctWords == 3)
        #expect(result.totalMatchedWords == 6)
    }
}
