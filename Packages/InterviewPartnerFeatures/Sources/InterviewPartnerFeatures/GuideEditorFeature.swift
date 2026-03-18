import Observation
import SwiftUI
import InterviewPartnerDomain

@MainActor
@Observable
public final class GuideEditorCoordinator: Identifiable {
    @ObservationIgnored
    private let guideRepository: any GuideRepository

    public let id: UUID
    let createdAt: Date

    var name: String
    var goal: String
    var questions: [GuideQuestionDraft]
    var expandedQuestionIDs: Set<UUID> = []
    var errorMessage: String?

    init(
        guideRepository: any GuideRepository,
        draft: GuideDraft
    ) {
        self.guideRepository = guideRepository
        id = draft.id
        createdAt = draft.createdAt
        name = draft.name
        goal = draft.goal
        questions = draft.questions.isEmpty ? [.init(orderIndex: 0)] : draft.questions
    }

    var navigationTitle: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guide Editor" : name
    }

    func addQuestion() {
        questions.append(GuideQuestionDraft(orderIndex: questions.count))
    }

    func moveQuestions(from offsets: IndexSet, to destination: Int) {
        questions.move(fromOffsets: offsets, toOffset: destination)
        reindexQuestions()
    }

    func removeQuestion(id: UUID) {
        questions.removeAll { $0.id == id }
        expandedQuestionIDs.remove(id)
        reindexQuestions()
    }

    func addSubPrompt(to questionID: UUID) {
        guard let index = questionIndex(for: questionID) else { return }
        questions[index].subPrompts.append("")
        expandedQuestionIDs.insert(questionID)
    }

    func removeSubPrompt(questionID: UUID, at subPromptIndex: Int) {
        guard let index = questionIndex(for: questionID),
              questions[index].subPrompts.indices.contains(subPromptIndex)
        else {
            return
        }

        questions[index].subPrompts.remove(at: subPromptIndex)
    }

    func setExpanded(_ isExpanded: Bool, for questionID: UUID) {
        if isExpanded {
            expandedQuestionIDs.insert(questionID)
        } else {
            expandedQuestionIDs.remove(questionID)
        }
    }

    func isExpanded(_ questionID: UUID) -> Bool {
        expandedQuestionIDs.contains(questionID)
    }

    func updateQuestionText(_ text: String, for questionID: UUID) {
        guard let index = questionIndex(for: questionID) else { return }
        questions[index].text = text
    }

    func updatePriority(_ priority: QuestionPriority, for questionID: UUID) {
        guard let index = questionIndex(for: questionID) else { return }
        questions[index].priority = priority
    }

    func updateSubPrompt(_ text: String, for questionID: UUID, at subPromptIndex: Int) {
        guard let index = questionIndex(for: questionID),
              questions[index].subPrompts.indices.contains(subPromptIndex)
        else {
            return
        }

        questions[index].subPrompts[subPromptIndex] = text
    }

    @discardableResult
    func save() -> Bool {
        do {
            _ = try guideRepository.saveGuide(
                GuideDraft(
                    id: id,
                    name: name,
                    goal: goal,
                    createdAt: createdAt,
                    questions: questions
                )
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func questionIndex(for questionID: UUID) -> Int? {
        questions.firstIndex { $0.id == questionID }
    }

    private func reindexQuestions() {
        questions = questions.enumerated().map { index, question in
            GuideQuestionDraft(
                id: question.id,
                text: question.text,
                priority: question.priority,
                orderIndex: index,
                subPrompts: question.subPrompts
            )
        }
    }
}

public struct GuideEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: GuideEditorCoordinator
    private let onSaved: () -> Void

    public init(
        coordinator: GuideEditorCoordinator,
        onSaved: @escaping () -> Void
    ) {
        _coordinator = State(initialValue: coordinator)
        self.onSaved = onSaved
    }

    public var body: some View {
        @Bindable var bindable = coordinator

        NavigationStack {
            Form {
                Section("Guide Details") {
                    TextField("Guide name", text: $bindable.name)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal / Context")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $bindable.goal)
                            .frame(minHeight: 120)
                    }
                }

                Section {
                    ForEach(coordinator.questions, id: \.id) { question in
                        QuestionEditorRow(
                            question: question,
                            isExpanded: Binding(
                                get: { coordinator.isExpanded(question.id) },
                                set: { coordinator.setExpanded($0, for: question.id) }
                            ),
                            text: Binding(
                                get: {
                                    coordinator.questions.first(where: { $0.id == question.id })?.text ?? ""
                                },
                                set: { coordinator.updateQuestionText($0, for: question.id) }
                            ),
                            priority: Binding(
                                get: {
                                    coordinator.questions.first(where: { $0.id == question.id })?.priority ?? .mustCover
                                },
                                set: { coordinator.updatePriority($0, for: question.id) }
                            ),
                            subPrompts: coordinator.questions.first(where: { $0.id == question.id })?.subPrompts ?? [],
                            onAddSubPrompt: { coordinator.addSubPrompt(to: question.id) },
                            onUpdateSubPrompt: { coordinator.updateSubPrompt($0, for: question.id, at: $1) },
                            onRemoveSubPrompt: { coordinator.removeSubPrompt(questionID: question.id, at: $0) },
                            onRemoveQuestion: { coordinator.removeQuestion(id: question.id) }
                        )
                    }
                    .onMove(perform: coordinator.moveQuestions)

                    Button("Add Question") {
                        coordinator.addQuestion()
                    }
                } header: {
                    HStack {
                        Text("Questions")
                        Spacer()
                        Text("Use Edit to reorder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = coordinator.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(coordinator.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        if coordinator.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
    }
}

private struct QuestionEditorRow: View {
    let question: GuideQuestionDraft
    @Binding var isExpanded: Bool
    @Binding var text: String
    @Binding var priority: QuestionPriority
    let subPrompts: [String]
    let onAddSubPrompt: () -> Void
    let onUpdateSubPrompt: (String, Int) -> Void
    let onRemoveSubPrompt: (Int) -> Void
    let onRemoveQuestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Question text", text: $text, axis: .vertical)
                .lineLimit(2...5)

            Picker("Priority", selection: $priority) {
                ForEach(QuestionPriority.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.menu)

            DisclosureGroup("Sub-prompts", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if subPrompts.isEmpty {
                        Text("Collapsed by default. Add optional follow-up prompts here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(subPrompts.enumerated()), id: \.offset) { index, subPrompt in
                            HStack(alignment: .top, spacing: 8) {
                                TextField(
                                    "Sub-prompt \(index + 1)",
                                    text: Binding(
                                        get: { subPrompt },
                                        set: { onUpdateSubPrompt($0, index) }
                                    ),
                                    axis: .vertical
                                )
                                .lineLimit(1...3)

                                Button(role: .destructive) {
                                    onRemoveSubPrompt(index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("Add Sub-prompt") {
                        onAddSubPrompt()
                    }
                }
                .padding(.top, 8)
            }

            Button(role: .destructive) {
                onRemoveQuestion()
            } label: {
                Label("Delete Question", systemImage: "trash")
            }
            .font(.footnote)
        }
        .padding(.vertical, 6)
    }
}
