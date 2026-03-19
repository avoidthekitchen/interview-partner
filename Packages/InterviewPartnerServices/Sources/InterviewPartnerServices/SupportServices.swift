import AVFAudio
import InterviewPartnerDomain

@MainActor
public final class DefaultWorkspaceGuideImporter: WorkspaceGuideImporter {
    public init() {}

    public func importGuides() throws -> [GuideDraft] {
        []
    }
}

@MainActor
public final class SystemPermissionManager: PermissionManager {
    public init() {}

    public func microphonePermissionState() -> MicrophonePermissionState {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
        #else
        return .granted
        #endif
    }

    public func requestMicrophonePermission() async -> MicrophonePermissionState {
        #if os(iOS)
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        return granted ? .granted : .denied
        #else
        return .granted
        #endif
    }
}

@MainActor
public final class StubKeychainStore: KeychainStore {
    private var values: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) throws -> String? {
        values[key]
    }

    public func setString(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    public func removeValue(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
