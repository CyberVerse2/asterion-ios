import Foundation

public enum AsterionIOSBuild {
    public static let scheme = "Asterion"
    public static let bundleID = "cyberverse.Asterion"
    public static let projectRelativePath = "apps/ios/Asterion.xcodeproj"
    public static let xcodebuildPath = "/usr/bin/xcodebuild"
    public static let xcrunPath = "/usr/bin/xcrun"
}

public struct BuildPlan: Equatable, Sendable {
    public var repoRoot: URL
    public var device: AppleDevice

    public init(repoRoot: URL, device: AppleDevice) {
        self.repoRoot = repoRoot
        self.device = device
    }

    public var projectPath: URL {
        repoRoot.appending(path: AsterionIOSBuild.projectRelativePath)
    }

    public var derivedDataPath: URL {
        repoRoot
            .appending(path: ".artifacts/ios/device")
            .appending(path: device.buildDestinationID)
    }

    public var appPath: URL {
        derivedDataPath.appending(path: "Build/Products/Debug-iphoneos/Asterion.app")
    }

    public var xcodebuildArguments: [String] {
        [
            "-project", projectPath.path,
            "-scheme", AsterionIOSBuild.scheme,
            "-destination", "id=\(device.buildDestinationID)",
            "-derivedDataPath", derivedDataPath.path,
            "-allowProvisioningUpdates",
            "-allowProvisioningDeviceRegistration",
            "build",
        ]
    }

    public var installArguments: [String] {
        [
            "devicectl", "device", "install", "app",
            "--device", device.installDeviceID,
            appPath.path,
        ]
    }

    public var launchArguments: [String] {
        [
            "devicectl", "device", "process", "launch",
            "--device", device.installDeviceID,
            AsterionIOSBuild.bundleID,
        ]
    }

    public func commandLines() -> [String] {
        [
            shellLine(AsterionIOSBuild.xcodebuildPath, xcodebuildArguments),
            shellLine(AsterionIOSBuild.xcrunPath, installArguments),
            shellLine(AsterionIOSBuild.xcrunPath, launchArguments),
        ]
    }

    private func shellLine(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map(Self.quote).joined(separator: " ")
    }

    private static func quote(_ value: String) -> String {
        if value.contains(where: { $0.isWhitespace || $0 == "'" }) {
            return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return value
    }
}

public enum AsterionRepo {
    public static let defaultPath = "/Users/thecyberverse/Code/Asterion"

    public static func containsProject(at url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appending(path: AsterionIOSBuild.projectRelativePath).path
        )
    }

    public static func resolve(
        override: String?,
        bundleURL: URL = Bundle.main.bundleURL,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> URL {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        var starts = [
            URL(fileURLWithPath: currentDirectory).standardizedFileURL,
            bundleURL.standardizedFileURL,
        ]
        if let git = gitRoot(from: currentDirectory) {
            starts.insert(git, at: 0)
        }

        var seen = Set<String>()
        for start in starts {
            var url = start
            for _ in 0..<16 {
                let path = url.path
                guard seen.insert(path).inserted else { break }
                if containsProject(at: url) {
                    return url
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }

        return URL(fileURLWithPath: defaultPath)
    }

    public static func gitRoot(from directory: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
