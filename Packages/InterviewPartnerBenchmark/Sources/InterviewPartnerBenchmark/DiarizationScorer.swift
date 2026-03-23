/// Scores speaker attribution accuracy by aligning hypothesis words
/// to reference words using edit distance, then checking speaker labels.
public enum DiarizationScorer {

    /// Scores diarization accuracy between reference and hypothesis transcripts.
    ///
    /// Uses edit distance alignment to pair words, then checks speaker labels
    /// on matched pairs (equal or substitution). Hypothesis speaker labels are
    /// mapped to reference labels sequentially: the first unique hypothesis
    /// speaker maps to the first unique reference speaker encountered, etc.
    ///
    /// - Parameters:
    ///   - reference: The ground truth words with speaker labels.
    ///   - hypothesis: The predicted words with speaker labels.
    /// - Returns: A ``DiarizationResult`` with accuracy, correct count, and total matched count.
    public static func score(
        reference: [LabeledWord],
        hypothesis: [LabeledWord]
    ) -> DiarizationResult {
        // Edge cases: both empty
        if reference.isEmpty && hypothesis.isEmpty {
            return DiarizationResult(accuracy: 100.0, correctWords: 0, totalMatchedWords: 0)
        }

        // Edge cases: one side empty
        if reference.isEmpty || hypothesis.isEmpty {
            return DiarizationResult(accuracy: 0.0, correctWords: 0, totalMatchedWords: 0)
        }

        // Step 1: Align words using edit distance
        let alignment = align(
            reference: reference.map { $0.word.lowercased() },
            hypothesis: hypothesis.map { $0.word.lowercased() }
        )

        // Step 2: Build sequential speaker label mapping from hypothesis → reference
        var speakerMap: [String: String] = [:]
        var mappedReferenceSpeakers: Set<String> = []

        // First pass: build mapping from matched pairs in alignment order
        for operation in alignment {
            switch operation {
            case .equal(let refIndex, let hypIndex),
                 .substitution(let refIndex, let hypIndex):
                let hypSpeaker = hypothesis[hypIndex].speaker
                let refSpeaker = reference[refIndex].speaker
                if speakerMap[hypSpeaker] == nil && !mappedReferenceSpeakers.contains(refSpeaker) {
                    speakerMap[hypSpeaker] = refSpeaker
                    mappedReferenceSpeakers.insert(refSpeaker)
                }
            case .insertion, .deletion:
                break
            }
        }

        // Step 3: Count correct attributions on matched word pairs
        var correctWords = 0
        var totalMatchedWords = 0

        for operation in alignment {
            switch operation {
            case .equal(let refIndex, let hypIndex),
                 .substitution(let refIndex, let hypIndex):
                totalMatchedWords += 1
                let mappedSpeaker = speakerMap[hypothesis[hypIndex].speaker]
                if mappedSpeaker == reference[refIndex].speaker {
                    correctWords += 1
                }
            case .insertion, .deletion:
                break
            }
        }

        let accuracy = totalMatchedWords > 0
            ? (Double(correctWords) / Double(totalMatchedWords)) * 100.0
            : 0.0

        return DiarizationResult(
            accuracy: accuracy,
            correctWords: correctWords,
            totalMatchedWords: totalMatchedWords
        )
    }
}

// MARK: - Edit Distance Alignment

extension DiarizationScorer {

    /// An alignment operation between reference and hypothesis sequences.
    enum AlignmentOperation: Sendable {
        /// Words match at the given indices.
        case equal(refIndex: Int, hypIndex: Int)
        /// Different words aligned together.
        case substitution(refIndex: Int, hypIndex: Int)
        /// Hypothesis has an extra word (no reference match).
        case insertion(hypIndex: Int)
        /// Reference word has no hypothesis match.
        case deletion(refIndex: Int)
    }

    /// Computes the edit distance alignment between reference and hypothesis word sequences.
    ///
    /// Uses the standard dynamic programming algorithm with backtrace to produce
    /// the optimal alignment.
    static func align(reference: [String], hypothesis: [String]) -> [AlignmentOperation] {
        let refCount = reference.count
        let hypCount = hypothesis.count

        // DP cost matrix: dp[i][j] = min edit distance for ref[0..<i] vs hyp[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: hypCount + 1), count: refCount + 1)

        // Initialize base cases
        for i in 0...refCount {
            dp[i][0] = i // all deletions
        }
        for j in 0...hypCount {
            dp[0][j] = j // all insertions
        }

        // Fill DP table
        for i in 1...refCount {
            for j in 1...hypCount {
                if reference[i - 1] == hypothesis[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] // equal, no cost
                } else {
                    let substitutionCost = dp[i - 1][j - 1] + 1
                    let deletionCost = dp[i - 1][j] + 1
                    let insertionCost = dp[i][j - 1] + 1
                    dp[i][j] = min(substitutionCost, min(deletionCost, insertionCost))
                }
            }
        }

        // Backtrace to recover alignment
        var operations: [AlignmentOperation] = []
        var i = refCount
        var j = hypCount

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && reference[i - 1] == hypothesis[j - 1] {
                operations.append(.equal(refIndex: i - 1, hypIndex: j - 1))
                i -= 1
                j -= 1
            } else if i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1 {
                operations.append(.substitution(refIndex: i - 1, hypIndex: j - 1))
                i -= 1
                j -= 1
            } else if i > 0 && dp[i][j] == dp[i - 1][j] + 1 {
                operations.append(.deletion(refIndex: i - 1))
                i -= 1
            } else {
                operations.append(.insertion(hypIndex: j - 1))
                j -= 1
            }
        }

        return operations.reversed()
    }
}
