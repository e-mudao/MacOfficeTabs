import Foundation

/// A snapshot belongs to a specific selection generation, including when a
/// user switches away and back to the same application during a scan.
public struct OfficeRoute {
    public struct Ticket: Equatable {
        public let app: OfficeApp
        fileprivate let generation: UInt64
    }
    private var generation: UInt64 = 0
    public private(set) var app: OfficeApp = .word
    public init() {}
    public mutating func select(_ app: OfficeApp) -> Ticket {
        generation &+= 1
        self.app = app
        return ticket
    }
    public var ticket: Ticket { Ticket(app:app,generation:generation) }
    public func accepts(_ ticket: Ticket) -> Bool { ticket == self.ticket }
}
