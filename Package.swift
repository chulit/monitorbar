// swift-tools-version: 5.9
import PackageDescription

// MonitorBar — a menu-bar-only system monitor. No main window, no
// dashboard: the popover is the whole app, plus a small Settings scene.
// Swift 5 language mode is deliberate: it keeps the build warning-light
// on current Xcode versions without strict-concurrency ceremony.
let package = Package(
  name: "MonitorBar",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "MonitorBar", targets: ["MonitorBarApp"]),
    .library(name: "MonitorKit", targets: ["MonitorKit"]),
  ],
  targets: [
    .target(name: "MonitorKit"),
    .executableTarget(
      name: "MonitorBarApp",
      dependencies: ["MonitorKit"]
    ),
    .testTarget(
      name: "MonitorKitTests",
      dependencies: ["MonitorKit"]
    ),
  ]
)
