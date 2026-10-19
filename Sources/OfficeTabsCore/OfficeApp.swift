import Foundation

public enum OfficeApp: String, CaseIterable {
    case word = "com.microsoft.Word"
    case excel = "com.microsoft.Excel"
    case powerPoint = "com.microsoft.Powerpoint"
    public init?(bundleID:String?) {
        guard let bundleID, let app = Self(rawValue:bundleID) else { return nil }
        self = app
    }
    public var name: String {
        switch self { case .word:return "Word"; case .excel:return "Excel"; case .powerPoint:return "PowerPoint" }
    }
}
