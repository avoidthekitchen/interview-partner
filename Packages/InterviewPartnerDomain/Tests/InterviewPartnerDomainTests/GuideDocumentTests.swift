import Foundation
import Testing
@testable import InterviewPartnerDomain

@Test func guideExportIncludesForwardCompatibilityStubs() throws {
    let draft = GuideDraft(
        name: "Leadership Loop",
        goal: "Understand how the candidate handled ambiguity.",
        createdAt: Date(timeIntervalSince1970: 1_710_000_000),
        questions: [
            GuideQuestionDraft(
                text: "Tell me about a difficult decision.",
                priority: .mustCover,
                orderIndex: 0,
                subPrompts: ["What tradeoffs did you weigh?"]
            ),
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let json = try String(
        decoding: encoder.encode(draft.exportDocument),
        as: UTF8.self
    )

    #expect(json.contains("\"branch\" : null"))
    #expect(json.contains("\"ai_scoring_prompt_override\" : null"))
    #expect(json.contains("\"must_cover\""))
}
