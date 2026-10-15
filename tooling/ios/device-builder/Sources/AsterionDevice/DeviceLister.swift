import DeviceBuilderCore
import Foundation

enum DeviceLister {
    static func list() async throws -> [AppleDevice] {
        try await Task.detached {
            try listBlocking()
        }.value
    }

    private static func listBlocking() throws -> [AppleDevice] {
        let jsonURL = FileManager.default.temporaryDirectory
            .appending(path: "asterion-device-list-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: AsterionIOSBuild.xcrunPath)
        process.arguments = [
            "devicectl", "list", "devices",
            "--json-output", jsonURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           FileManager.default.fileExists(atPath: jsonURL.path) {
            let data = try Data(contentsOf: jsonURL)
            return try DeviceListParser.parseDevicectlJSON(data)
        }

        return try listFromXCTrace()
    }

    private static func listFromXCTrace() throws -> [AppleDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AsterionIOSBuild.xcrunPath)
        process.arguments = ["xctrace", "list", "devices"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw DeviceListerError.commandFailed(process.terminationStatus, text)
        }
        return DeviceListParser.parseXCTraceList(text)
    }
}

enum DeviceListerError: LocalizedError {
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let status, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Device listing failed (exit \(status))."
            }
            return "Device listing failed (exit \(status)):\n\(trimmed)"
        }
    }
}
