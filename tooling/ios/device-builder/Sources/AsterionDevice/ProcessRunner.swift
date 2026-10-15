import Darwin
import Foundation

@MainActor
final class ProcessRunner {
    private var process: Process?
    private var processGroup: pid_t = 0

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        onOutput: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardInput = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let handle = pipe.fileHandleForReading

            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else {
                    return
                }
                Task { @MainActor in
                    onOutput(chunk)
                }
            }

            process.terminationHandler = { finished in
                handle.readabilityHandler = nil
                let leftover = (try? handle.readToEnd()) ?? Data()
                let status = finished.terminationStatus
                Task { @MainActor in
                    if !leftover.isEmpty, let chunk = String(data: leftover, encoding: .utf8), !chunk.isEmpty {
                        onOutput(chunk)
                    }
                    continuation.resume(returning: status)
                }
            }

            do {
                try process.run()
                self.process = process
                self.processGroup = process.processIdentifier
                _ = setpgid(process.processIdentifier, process.processIdentifier)
            } catch {
                handle.readabilityHandler = nil
                Task { @MainActor in
                    onOutput("Failed to start \(executable): \(error.localizedDescription)\n")
                    continuation.resume(returning: 127)
                }
            }
        }
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        let group = processGroup != 0 ? processGroup : process.processIdentifier
        if kill(-group, SIGTERM) != 0 {
            process.terminate()
        }
    }
}
