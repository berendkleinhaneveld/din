// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Din",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Din",
            path: "Din",
            exclude: ["Info.plist", "Din.entitlements"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Din/Info.plist"])
            ]
        )
    ]
)
