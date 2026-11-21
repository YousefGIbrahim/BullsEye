// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BullseyeModelChecks",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BullseyeCore", targets: ["BullseyeCore"])],
    targets: [
        .target(name: "BullseyeCore", path: "bullseye", exclude: [
            "Assets.xcassets", "Info-Debug.plist", "Info-Release.plist", "MyApp.swift", "ContentView.swift", "Theme.swift",
            "AudioController.swift", "AudioSessionCoordinator.swift", "CaptureView.swift", "MappingViews.swift", "ServiceMatcher.swift",
            "StudentViews.swift", "Suggestions.swift", "Tracking.swift", "AutomaticGuidance.swift", "RoomEditor.swift",
            "BullseyeIcon60@2x.png", "BullseyeIcon60@3x.png", "BullseyeIcon76@2x.png", "BullseyeIcon83.5@2x.png"
        ], sources: ["Models.swift", "TurnGuidance.swift"]),
        .testTarget(name: "BullseyeCoreTests", dependencies: ["BullseyeCore"], path: "Verification")
    ]
)
