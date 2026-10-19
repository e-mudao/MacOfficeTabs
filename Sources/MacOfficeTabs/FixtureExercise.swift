import AppKit
import OfficeTabsCore

/// Only explicitly supplied, generated test files can be exercised; never select by title.
func exerciseFixtures(root: String) -> Int32 {
    let client = AXClient()
    defer { client.stopObserving() }
    let result = client.scan()
    let folder = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath().path + "/"
    let fixtures = result.details.filter {
        guard let url = $0.record.fileURL, url.isFileURL else { return false }
        return url.resolvingSymlinksInPath().path.hasPrefix(folder)
    }.sorted { $0.record.fileURL!.path < $1.record.fileURL!.path }
    guard fixtures.count == 10 else {
        fputs("Expected exactly 10 open test fixtures under specified directory; found \(fixtures.count). No activation performed.\n", stderr)
        return 4
    }
    var attempts: [[String: Any]] = []
    for index in 0..<100 {
        let target = fixtures[index % fixtures.count].record
        let started = ProcessInfo.processInfo.systemUptime
        let activated = client.activate(target.id)
        switch activated {
        case .confirmed(let requested, let focused, let frontmostPID):
            attempts.append(["iteration": index + 1, "requested": requested.uuidString,
                             "focused": focused.uuidString, "frontmostPID": frontmostPID,
                             "confirmed": requested == focused && frontmostPID == target.processID,
                             "seconds": ProcessInfo.processInfo.systemUptime - started])
        case .failed(let message):
            attempts.append(["iteration": index + 1, "requested": target.id.uuidString, "confirmed": false, "error": message])
        }
        if case .failed = activated { break }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
    let passed = attempts.count == 100 && attempts.allSatisfy { $0["confirmed"] as? Bool == true }
    let report: [String: Any] = ["sampleCount": fixtures.count, "allConfirmed": passed,
                              "fixtureWindows": fixtures.map { ["id": $0.record.id.uuidString, "name": $0.record.title] },
                              "attempts": attempts, "keyboardInputVerified": false]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
    return passed ? 0 : 5
}
