import Observation
import SwiftUI
import InterviewPartnerDomain

@MainActor
@Observable
final class GuideListCoordinator {
    @ObservationIgnored
    private let guideRepository: any GuideRepository

    var guides: [GuideSummary] = []
    var errorMessage: String?
    var editor: GuideEditorCoordinator?

    init(guideRepository: any GuideRepository) {
        self.guideRepository = guideRepository
    }

    func load() {
        do {
            guides = try guideRepository.fetchGuides()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentNewGuideEditor() {
        editor = GuideEditorCoordinator(
            guideRepository: guideRepository,
            draft: .empty
        )
    }

    func presentEditor(for guideID: UUID) {
        do {
            guard let draft = try guideRepository.fetchGuide(id: guideID) else {
                errorMessage = "That guide could not be loaded."
                return
            }

            editor = GuideEditorCoordinator(
                guideRepository: guideRepository,
                draft: draft
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        do {
            for index in offsets {
                try guideRepository.deleteGuide(id: guides[index].id)
            }
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ guide: GuideSummary) {
        do {
            _ = try guideRepository.duplicateGuide(id: guide.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct GuideListView: View {
    @State private var coordinator: GuideListCoordinator

    public init(guideRepository: any GuideRepository) {
        _coordinator = State(initialValue: GuideListCoordinator(guideRepository: guideRepository))
    }

    public var body: some View {
        @Bindable var bindable = coordinator

        List {
            if coordinator.guides.isEmpty {
                ContentUnavailableView(
                    "No Guides Yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Create reusable guide templates with questions, priorities, and sub-prompts.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Guides") {
                    ForEach(coordinator.guides) { guide in
                        Button {
                            coordinator.presentEditor(for: guide.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(guide.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !guide.goal.isEmpty {
                                    Text(guide.goal)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text("\(guide.questionCount) question\(guide.questionCount == 1 ? "" : "s")")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Duplicate") {
                                coordinator.duplicate(guide)
                            }

                            Button("Edit") {
                                coordinator.presentEditor(for: guide.id)
                            }
                        }
                    }
                    .onDelete(perform: coordinator.delete)
                }
            }
        }
        .navigationTitle("Guides")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Guide") {
                    coordinator.presentNewGuideEditor()
                }
            }
        }
        .task {
            coordinator.load()
        }
        .sheet(item: $bindable.editor) { editor in
            GuideEditorView(coordinator: editor) {
                coordinator.editor = nil
                coordinator.load()
            }
        }
        .alert(
            "Guide Error",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "Unknown error")
        }
    }
}
