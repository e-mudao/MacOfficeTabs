import Foundation

/// Enumeration is space-local in some apps. Retain object references, but require
/// a fresh probe for every returned candidate. Unknown probes must throw.
public final class WindowInventory<Token: Equatable> {
    private var processID: Int32?
    private var candidates: [Token] = []
    public init() {}
    public func clear() { processID = nil; candidates = [] }
    public func invalidate(processID:Int32,token:Token) {
        guard self.processID == processID else { return }
        candidates.removeAll { $0 == token }
    }
    public func remember(processID: Int32, token: Token) {
        if self.processID != processID { clear(); self.processID = processID }
        if !candidates.contains(token) { candidates.append(token) }
    }
    public func resolve(processID: Int32, discovered: [Token],
                        retainAcrossAbsence: (Token) throws -> Bool = { _ in true },
                        isLive: (Token) throws -> Bool) throws -> [Token] {
        if self.processID != processID { clear(); self.processID = processID }
        for token in discovered { remember(processID:processID,token:token) }
        var live: [Token] = []
        for token in candidates {
            guard try isLive(token) else { continue }
            // Current discoveries always reach safety checks. Only absent objects
            // need the stricter retention classification; unknown must throw.
            let shouldRetain = try discovered.contains(token) || retainAcrossAbsence(token)
            if shouldRetain {
                live.append(token)
            }
        }
        candidates = live
        return live
    }
}
