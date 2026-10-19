import Foundation

public struct WindowRecord: Equatable {
    public let id: UUID
    public let processID: Int32
    public var title: String
    public var fileURL: URL?
    public init(id: UUID, processID: Int32, title: String, fileURL: URL? = nil) {
        self.id = id; self.processID = processID; self.title = title; self.fileURL = fileURL
    }
}

/// Tokens must represent object equivalence, never a document title.
public final class IdentityStore<Token: Equatable> {
    private struct Entry { let pid: Int32; let token: Token; let id: UUID }
    private var entries: [Entry] = []
    public init() {}
    public func identity(processID: Int32, token: Token) -> UUID {
        if let entry = entries.first(where: { $0.pid == processID && $0.token == token }) { return entry.id }
        let id = UUID(); entries.append(Entry(pid: processID, token: token, id: id)); return id
    }
    public func retain(processID: Int32, tokens: [Token]) {
        entries.removeAll { $0.pid == processID && !tokens.contains($0.token) }
    }
    public func remove(processID: Int32) { entries.removeAll { $0.pid == processID } }
    /// Absence from enumeration is not evidence of destruction (for example, another Space).
    public func invalidate(processID: Int32, tokens: [Token]) {
        entries.removeAll { $0.pid == processID && tokens.contains($0.token) }
    }
}

public struct DocumentRecord {
    public let id: UUID
    public let fileURL: URL
    public let processID: Int32
    public let windowIDs: Set<UUID>
}
public struct DocumentRegistry {
    public private(set) var documents: [DocumentRecord] = []
    public init() {}
    public mutating func reconcile(_ windows: [WindowRecord]) {
        struct Key: Hashable { let pid: Int32; let url: URL }
        let groups = Dictionary(grouping: windows.filter { $0.fileURL != nil }) {
            Key(pid: $0.processID, url: $0.fileURL!.standardized)
        }
        documents = groups.map { key, windows in
            let previous = documents.first { $0.processID == key.pid && $0.fileURL == key.url }
            return DocumentRecord(id: previous?.id ?? UUID(), fileURL: key.url,
                                  processID: key.pid, windowIDs: Set(windows.map(\.id)))
        }
    }
}
public enum ScanOutcome { case success([WindowRecord]), failure(String), denied }
public struct WindowState {
    public private(set) var windows: [WindowRecord] = []
    public private(set) var canControl = false
    public init() {}
    public mutating func apply(_ outcome: ScanOutcome) {
        switch outcome {
        case .success(let records): windows = records; canControl = true
        case .failure: canControl = false
        case .denied: windows = []; canControl = false
        }
    }
}
public enum ActivationStatus: Equatable { case pending, confirmed, failed }
public struct ActivationVerifier {
    private let target: UUID
    private let processID: Int32
    private let deadline: TimeInterval
    public init(target: UUID, processID: Int32, deadline: TimeInterval) {
        self.target = target; self.processID = processID; self.deadline = deadline
    }
    public func evaluate(focused: UUID?, frontmostPID: Int32?, now: TimeInterval) -> ActivationStatus {
        guard now < deadline else { return .failed }
        return focused == target && frontmostPID == processID ? .confirmed : .pending
    }
}

public enum ControlSafety {
    public static func blocksWindow(isStandard: Bool, isModal: Bool?, isSheet: Bool) -> Bool {
        isSheet || isModal == true || (!isStandard && isModal == nil)
    }
    public static func rejection(hasTarget: Bool, focusedStandard: Bool, childrenInspected: Bool, blockingWindow: Bool) -> String? {
        if !hasTarget { return "targetMissing" }
        if !focusedStandard { return "focusUnknown" }
        if blockingWindow { return "blockingWindow" }
        if !childrenInspected { return "childrenUnknown" }
        return nil
    }
    public static func permits(hasTarget: Bool, focusedStandard: Bool, childrenInspected: Bool, blockingWindow: Bool) -> Bool {
        rejection(hasTarget: hasTarget, focusedStandard: focusedStandard, childrenInspected: childrenInspected, blockingWindow: blockingWindow) == nil
    }
    public static func validFrame(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height].allSatisfy { $0.isFinite && abs($0) < 1_000_000 }
            && frame.size.width > 0 && frame.size.height > 0
    }
}
