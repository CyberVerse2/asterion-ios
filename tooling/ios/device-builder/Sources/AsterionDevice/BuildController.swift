import DeviceBuilderCore
import Foundation
import Observation

enum BuildStatus: Equatable, Sendable {
    case idle
    case running(String)
    case succeeded
    case failed(String)
    case cancelled

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var banner: String {
        switch self {
        case .idle:
            "Ready"
        case .running(let phase):
            phase
        case .succeeded:
            "Installed and launched"
        case .failed(let message):
            message
        case .cancelled:
            "Cancelled"
        }
    }
}

@MainActor
@Observable
final class BuildController {
    var devices: [AppleDevice] = []
    var selectedID: String?
    var log = ""
    var status: BuildStatus = .idle
    var repoPath: String
    var isRefreshing = false
    var listError: String?

    @ObservationIgnored
    private let runner = ProcessRunner()
    @ObservationIgnored
    private var cancelled = false

    private static let repoPathKey = "asterion.device.repoPath"
    private static let lastDeviceKey = "asterion.device.lastUDID"
    private static let maxLogCharacters = 400_000

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.repoPathKey)
        let resolved = AsterionRepo.resolve(override: stored)
        repoPath = resolved.path
        selectedID = UserDefaults.standard.string(forKey: Self.lastDeviceKey)
    }

    var selectedDevice: AppleDevice? {
        devices.first { $0.id == selectedID }
    }

    var repoURL: URL {
        URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath)
    }

    var repoLooksValid: Bool {
        AsterionRepo.containsProject(at: repoURL)
    }

    var canBuild: Bool {
        !status.isRunning && selectedDevice != nil && repoLooksValid
    }

    func persistRepoPath() {
        UserDefaults.standard.set(repoPath, forKey: Self.repoPathKey)
    }

    func persistSelection() {
        UserDefaults.standard.set(selectedID, forKey: Self.lastDeviceKey)
    }

    func refreshDevices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let listed = try await DeviceLister.list()
            devices = listed
            listError = listed.isEmpty ? "No physical iPhone or iPad found." : nil
            if let selectedID, listed.contains(where: { $0.id == selectedID }) {
                return
            }
            if let last = UserDefaults.standard.string(forKey: Self.lastDeviceKey),
               listed.contains(where: { $0.id == last }) {
                selectedID = last
            } else {
                selectedID = listed.first?.id
            }
            persistSelection()
        } catch {
            listError = error.localizedDescription
            appendLog("Device listing failed: \(error.localizedDescription)\n")
        }
    }

    func build() async {
        guard !status.isRunning, let device = selectedDevice else { return }
        cancelled = false
        persistRepoPath()
        persistSelection()
        log = ""
        status = .running("Preparing")

        let plan = BuildPlan(repoRoot: repoURL, device: device)
        appendLog("Repo: \(plan.repoRoot.path)\n")
        appendLog("Device: \(device.title) · \(device.name) · \(device.buildDestinationID)\n")
        appendLog("Derived data: \(plan.derivedDataPath.path)\n\n")

        let steps: [(String, String, [String])] = [
            ("Building", AsterionIOSBuild.xcodebuildPath, plan.xcodebuildArguments),
            ("Installing", AsterionIOSBuild.xcrunPath, plan.installArguments),
            ("Launching", AsterionIOSBuild.xcrunPath, plan.launchArguments),
        ]

        for (phase, executable, arguments) in steps {
            if cancelled {
                status = .cancelled
                appendLog("\nCancelled.\n")
                return
            }

            status = .running(phase)
            appendLog("\n$ \(([executable] + arguments).joined(separator: " "))\n\n")

            let code = await runner.run(
                executable: executable,
                arguments: arguments,
                workingDirectory: plan.repoRoot,
                onOutput: { [weak self] chunk in
                    self?.appendLog(chunk)
                }
            )

            if cancelled {
                status = .cancelled
                appendLog("\nCancelled.\n")
                return
            }

            if code != 0 {
                status = .failed("\(phase) failed (exit \(code))")
                appendLog("\n\(phase) failed with exit \(code).\n")
                return
            }
        }

        status = .succeeded
        appendLog("\nAsterion is running on \(device.title).\n")
    }

    func cancel() {
        guard status.isRunning else { return }
        cancelled = true
        runner.terminate()
        appendLog("\nStopping process group…\n")
    }

    private func appendLog(_ chunk: String) {
        log.append(chunk)
        if log.count > Self.maxLogCharacters {
            log = String(log.suffix(Self.maxLogCharacters * 3 / 4))
        }
    }
}
