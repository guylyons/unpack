import Foundation

/// Runs a command-line tool, streaming stdout and collecting stderr.
/// Cancelling the calling task terminates the process.
enum ProcessRunner {
    struct Result: Sendable {
        var exitCode: Int32
        var stderr: String
        var wasCancelled: Bool
    }

    static func run(
        _ executable: URL,
        arguments: [String],
        onStdout: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // No stdin: a tool that wants to prompt (e.g. for a password) fails fast instead of hanging.
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stderrData = LockedData()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { onStdout(String(decoding: data, as: UTF8.self)) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrData.append(handle.availableData)
        }

        let cancelled = LockedFlag()
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                    // Cancelled between the handler being installed and launch.
                    if cancelled.isSet { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancelled.set()
            if process.isRunning { process.terminate() }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if let rest = try? stdout.fileHandleForReading.readToEnd(), !rest.isEmpty {
            onStdout(String(decoding: rest, as: UTF8.self))
        }
        if let rest = try? stderr.fileHandleForReading.readToEnd() {
            stderrData.append(rest)
        }

        return Result(exitCode: exitCode, stderr: stderrData.string, wasCancelled: cancelled.isSet)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ more: Data) {
        lock.withLock { data.append(more) }
    }

    var string: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
