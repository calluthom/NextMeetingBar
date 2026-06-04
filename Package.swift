// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextMeetingBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NextMeetingBar",
            path: "Sources/NextMeetingBar",
            // Swift 5 language mode keeps the Timer/NotificationCenter closures
            // as warnings rather than strict-concurrency errors for this small app.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
