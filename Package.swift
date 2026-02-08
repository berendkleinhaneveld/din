// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Box",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Box",
            path: "Box",
            exclude: ["Info.plist", "Box.entitlements"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Box/Info.plist"])
            ]
        )
    ]
)
