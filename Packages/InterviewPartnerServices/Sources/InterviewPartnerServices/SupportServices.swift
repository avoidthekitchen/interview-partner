import InterviewPartnerDomain

@MainActor
public final class DefaultWorkspaceGuideImporter: WorkspaceGuideImporter {
    public init() {}

    public func importGuides() throws -> [GuideDraft] {
        []
    }
}

@MainActor
public final class StubPermissionManager: PermissionManager {
    public init() {}

    public func microphonePermissionState() -> MicrophonePermissionState {
        .notDetermined
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
