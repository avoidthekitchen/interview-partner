import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import InterviewPartnerDomain

@MainActor
@Observable
final class SettingsCoordinator {
    @ObservationIgnored
    private let workspaceExporter: any WorkspaceExporter

    var workspaceStatus: WorkspaceStatus
    var errorMessage: String?
    var isShowingFolderPicker = false

    init(workspaceExporter: any WorkspaceExporter) {
        self.workspaceExporter = workspaceExporter
        workspaceStatus = workspaceExporter.currentWorkspaceStatus()
    }

    func reload() {
        workspaceStatus = workspaceExporter.currentWorkspaceStatus()
    }

    func beginFolderSelection() {
        isShowingFolderPicker = true
    }

    func saveSelectedFolder(_ url: URL) {
        do {
            workspaceStatus = try workspaceExporter.saveWorkspaceBookmark(for: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct SettingsView: View {
    @State private var coordinator: SettingsCoordinator
    private let onWorkspaceUpdated: () -> Void

    public init(
        workspaceExporter: any WorkspaceExporter,
        onWorkspaceUpdated: @escaping () -> Void = {}
    ) {
        _coordinator = State(initialValue: SettingsCoordinator(workspaceExporter: workspaceExporter))
        self.onWorkspaceUpdated = onWorkspaceUpdated
    }

    public var body: some View {
        WorkspaceSettingsContent(
            coordinator: coordinator,
            title: "Workspace",
            subtitle: "Pick an iCloud Drive folder once. The app stores a security-scoped bookmark and reuses it on restart.",
            onWorkspaceUpdated: onWorkspaceUpdated
        )
        .navigationTitle("Settings")
    }
}

struct WorkspaceSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: SettingsCoordinator
    private let onWorkspaceUpdated: () -> Void

    init(
        workspaceExporter: any WorkspaceExporter,
        onWorkspaceUpdated: @escaping () -> Void
    ) {
        _coordinator = State(initialValue: SettingsCoordinator(workspaceExporter: workspaceExporter))
        self.onWorkspaceUpdated = onWorkspaceUpdated
    }

    var body: some View {
        NavigationStack {
            WorkspaceSettingsContent(
                coordinator: coordinator,
                title: "Workspace Setup",
                subtitle: "Before the real session flow arrives in Sprint 2, choose where guide JSON and session exports should be written.",
                onWorkspaceUpdated: {
                    onWorkspaceUpdated()
                    dismiss()
                }
            )
            .navigationTitle("Workspace Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WorkspaceSettingsContent: View {
    @Bindable var coordinator: SettingsCoordinator
    let title: String
    let subtitle: String
    let onWorkspaceUpdated: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                    Text("Current destination: \(coordinator.workspaceStatus.storageDescription)")
                        .font(.subheadline.monospaced())
                    Text(coordinator.workspaceStatus.resolvedBaseURL.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Section("Status") {
                LabeledContent("iCloud Drive") {
                    Text(coordinator.workspaceStatus.iCloudDriveAvailable ? "Available" : "Unavailable")
                }
                LabeledContent("Bookmark") {
                    Text(coordinator.workspaceStatus.hasBookmark ? "Configured" : "Missing")
                }
                LabeledContent("Storage") {
                    Text(
                        coordinator.workspaceStatus.storageLocation == .securityScopedBookmark
                            ? "Security-scoped folder"
                            : "App documents fallback"
                    )
                }
            }

            if let warningMessage = coordinator.workspaceStatus.warningMessage {
                Section {
                    Text(warningMessage)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Choose Workspace Folder") {
                    coordinator.beginFolderSelection()
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("Guide saves already export JSON to `InterviewPartner/guides/` inside the selected workspace folder.")
            }
        }
        .task {
            coordinator.reload()
        }
        .sheet(isPresented: $coordinator.isShowingFolderPicker) {
            WorkspaceFolderPicker { url in
                coordinator.saveSelectedFolder(url)
                onWorkspaceUpdated()
            }
        }
        .alert(
            "Workspace Error",
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

private struct WorkspaceFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let folderURL = urls.first else { return }
            onPick(folderURL)
        }
    }
}
