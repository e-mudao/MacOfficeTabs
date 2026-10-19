import Foundation

/// Discovery identity is distinct from a window identity. Labels only invalidate
/// reused sources; they never locate a target or establish an association.
public final class MenuCandidates<Token: Equatable> {
    public struct Entry {
        public let id: UUID
        public let token: Token
        public let title: String
        public fileprivate(set) var windowID: UUID?
    }
    public private(set) var entries: [Entry] = []
    private var processID: Int32?
    public init() {}
    @discardableResult public func reconcile(processID: Int32, sources: [(Token,String)]) -> [Entry] {
        if self.processID != processID { clear(); self.processID = processID }
        let old = entries
        entries = sources.map { token,title in
            old.first(where: { $0.token == token && $0.title == title })
                ?? Entry(id:UUID(),token:token,title:title,windowID:nil)
        }
        return entries
    }
    @discardableResult public func associate(_ id: UUID, windowID: UUID, selectedIDs: [UUID], frontmost: Bool, standardFocus: Bool) -> Bool {
        guard frontmost, standardFocus, selectedIDs == [id], let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        for i in entries.indices where i != index && entries[i].windowID == windowID { entries[i].windowID = nil }
        entries[index].windowID = windowID
        return true
    }
    /// Highlight only a freshly observed window whose source association has
    /// already been proved. Native menu checkmarks may lag after editing resumes.
    public func isFocused(_ id: UUID, focusedWindowID: UUID?) -> Bool {
        guard let focusedWindowID, let entry = entries.first(where:{ $0.id == id }) else { return false }
        return entry.windowID == focusedWindowID
    }
    public func clear() { entries = []; processID = nil }
}
