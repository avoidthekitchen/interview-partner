import Testing
@testable import InterviewPartnerBenchmark

@Suite("WERScorer Tests")
struct WERScorerTests {

    // MARK: - Perfect match

    @Test("Perfect match yields 100% accuracy")
    func perfectMatch() {
        let result = WERScorer.score(
            reference: "the cat sat on the mat",
            hypothesis: "the cat sat on the mat"
        )

        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.accuracy == 100.0)
    }

    // MARK: - Complete mismatch

    @Test("Complete mismatch yields 0% accuracy (all substitutions)")
    func completeMismatch() {
        let result = WERScorer.score(
            reference: "the cat sat",
            hypothesis: "a dog stood"
        )

        #expect(result.substitutions == 3)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.accuracy == 0.0)
    }

    // MARK: - Insertions only

    @Test("Hypothesis with extra words counts insertions")
    func insertionsOnly() {
        // Reference: "the cat" (2 words)
        // Hypothesis: "the big fat cat" (4 words)
        // Optimal alignment: "the" match, insert "big", insert "fat", "cat" match
        let result = WERScorer.score(
            reference: "the cat",
            hypothesis: "the big fat cat"
        )

        #expect(result.substitutions == 0)
        #expect(result.insertions == 2)
        #expect(result.deletions == 0)
        // WER = 2/2 = 1.0, accuracy = 0%
        #expect(result.accuracy == 0.0)
    }

    // MARK: - Deletions only

    @Test("Hypothesis missing words counts deletions")
    func deletionsOnly() {
        // Reference: "the big fat cat" (4 words)
        // Hypothesis: "the cat" (2 words)
        // Optimal alignment: "the" match, delete "big", delete "fat", "cat" match
        let result = WERScorer.score(
            reference: "the big fat cat",
            hypothesis: "the cat"
        )

        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 2)
        // WER = 2/4 = 0.5, accuracy = 50%
        #expect(result.accuracy == 50.0)
    }

    // MARK: - Mixed errors

    @Test("Mixed substitutions, insertions, and deletions")
    func mixedErrors() {
        // Reference: "the cat sat on the mat" (6 words)
        // Hypothesis: "a cat sit on mat" (5 words)
        // Alignment: sub(the->a), match(cat), sub(sat->sit), match(on), del(the), match(mat)
        // S=2, I=0, D=1 => WER = 3/6 = 0.5
        let result = WERScorer.score(
            reference: "the cat sat on the mat",
            hypothesis: "a cat sit on mat"
        )

        #expect(result.substitutions == 2)
        #expect(result.insertions == 0)
        #expect(result.deletions == 1)
        #expect(result.accuracy == 50.0)
    }

    // MARK: - Empty inputs

    @Test("Both empty yields 100% accuracy")
    func bothEmpty() {
        let result = WERScorer.score(reference: "", hypothesis: "")

        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.accuracy == 100.0)
    }

    @Test("Empty reference with non-empty hypothesis yields 0% accuracy")
    func emptyReference() {
        let result = WERScorer.score(reference: "", hypothesis: "some words here")

        #expect(result.insertions == 3)
        #expect(result.accuracy == 0.0)
    }

    @Test("Non-empty reference with empty hypothesis yields 0% accuracy")
    func emptyHypothesis() {
        let result = WERScorer.score(reference: "some words here", hypothesis: "")

        #expect(result.deletions == 3)
        #expect(result.accuracy == 0.0)
    }

    // MARK: - Single-word inputs

    @Test("Single matching word yields 100% accuracy")
    func singleWordMatch() {
        let result = WERScorer.score(reference: "hello", hypothesis: "hello")

        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.accuracy == 100.0)
    }

    @Test("Single word substitution yields 0% accuracy")
    func singleWordSubstitution() {
        let result = WERScorer.score(reference: "hello", hypothesis: "goodbye")

        #expect(result.substitutions == 1)
        #expect(result.accuracy == 0.0)
    }

    // MARK: - Text normalization

    @Test("Normalization lowercases and strips punctuation before scoring")
    func normalization() {
        let result = WERScorer.score(
            reference: "The Cat, sat on the mat!",
            hypothesis: "the cat sat on the mat"
        )

        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.accuracy == 100.0)
    }

    @Test("Normalization handles apostrophes consistently")
    func normalizationApostrophes() {
        let result = WERScorer.score(
            reference: "don't stop",
            hypothesis: "don't stop"
        )

        #expect(result.accuracy == 100.0)
    }
}
