import Foundation

/// The result of a Word Error Rate comparison.
public struct WERResult: Sendable, Equatable {
    /// Number of substituted words.
    public let substitutions: Int
    /// Number of inserted words (extra words in hypothesis).
    public let insertions: Int
    /// Number of deleted words (words missing from hypothesis).
    public let deletions: Int
    /// Accuracy as a percentage: `(1 - WER) * 100`, clamped to [0, 100].
    public let accuracy: Double
}

/// Computes Word Error Rate between a reference transcript and a hypothesis.
public enum WERScorer {

    /// Score a hypothesis against a reference using word-level edit distance.
    ///
    /// Both strings are normalized (lowercased, punctuation stripped) before comparison.
    public static func score(reference: String, hypothesis: String) -> WERResult {
        let refWords = normalize(reference)
        let hypWords = normalize(hypothesis)

        // Edge cases
        if refWords.isEmpty && hypWords.isEmpty {
            return WERResult(substitutions: 0, insertions: 0, deletions: 0, accuracy: 100.0)
        }
        if refWords.isEmpty {
            return WERResult(substitutions: 0, insertions: hypWords.count, deletions: 0, accuracy: 0.0)
        }
        if hypWords.isEmpty {
            return WERResult(substitutions: 0, insertions: 0, deletions: refWords.count, accuracy: 0.0)
        }

        let (s, i, d) = editDistance(reference: refWords, hypothesis: hypWords)
        let wer = Double(s + i + d) / Double(refWords.count)
        let accuracy = max(0.0, (1.0 - wer) * 100.0)

        return WERResult(substitutions: s, insertions: i, deletions: d, accuracy: accuracy)
    }

    // MARK: - Private

    /// Edit operation used during back-tracing.
    private enum EditOp: Int {
        case matchOrSubstitution = 0
        case insertion = 1
        case deletion = 2
    }

    /// Normalize text: lowercase, strip punctuation, split into words.
    private static func normalize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let stripped = lowered.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
                || CharacterSet.whitespaces.contains($0)
                || $0 == "'"
        }
        return String(stripped)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    /// Word-level edit distance returning (substitutions, insertions, deletions).
    ///
    /// Uses the standard dynamic programming approach with back-tracing to
    /// classify each edit operation.
    private static func editDistance(
        reference ref: [String],
        hypothesis hyp: [String]
    ) -> (substitutions: Int, insertions: Int, deletions: Int) {
        let n = ref.count
        let m = hyp.count

        // dp[i][j] = minimum edit distance for ref[0..<i] vs hyp[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        var ops = Array(
            repeating: Array(repeating: EditOp.matchOrSubstitution, count: m + 1),
            count: n + 1
        )

        for i in 1...n {
            dp[i][0] = i
            ops[i][0] = .deletion
        }
        for j in 1...m {
            dp[0][j] = j
            ops[0][j] = .insertion
        }

        for i in 1...n {
            for j in 1...m {
                let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                let sub = dp[i - 1][j - 1] + cost
                let del = dp[i - 1][j] + 1
                let ins = dp[i][j - 1] + 1

                let minVal = min(sub, del, ins)
                dp[i][j] = minVal

                if minVal == sub {
                    ops[i][j] = .matchOrSubstitution
                } else if minVal == del {
                    ops[i][j] = .deletion
                } else {
                    ops[i][j] = .insertion
                }
            }
        }

        // Back-trace to count operations
        var substitutions = 0
        var insertions = 0
        var deletions = 0
        var i = n
        var j = m

        while i > 0 || j > 0 {
            switch ops[i][j] {
            case .matchOrSubstitution:
                if ref[i - 1] != hyp[j - 1] {
                    substitutions += 1
                }
                i -= 1
                j -= 1
            case .insertion:
                insertions += 1
                j -= 1
            case .deletion:
                deletions += 1
                i -= 1
            }
        }

        return (substitutions, insertions, deletions)
    }
}
