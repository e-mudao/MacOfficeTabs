// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacOfficeTabs", platforms: [.macOS(.v13)],
    products: [.executable(name: "MacOfficeTabs", targets: ["MacOfficeTabs"]),
               .library(name: "OfficeTabsCore", targets: ["OfficeTabsCore"])],
    targets: [.target(name: "OfficeTabsCore"),
              .executableTarget(name: "MacOfficeTabs", dependencies: ["OfficeTabsCore"]),
              .testTarget(name: "OfficeTabsCoreTests", dependencies: ["OfficeTabsCore"])])
