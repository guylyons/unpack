import Foundation

/// Fallback engine: the libarchive `bsdtar` built into macOS. Handles zip,
/// tar (+ gz/bz2/xz), 7z, cpio, ISO and most RAR files, without progress.
struct LibarchiveEngine: ArchiveEngine {
    var executable = URL(filePath: "/usr/bin/bsdtar")

    var displayName: String { "libarchive" }

    func extract(
        _ archive: URL,
        into directory: URL,
        password: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ExtractionError.engineUnavailable
        }

        var arguments = ["-x", "-f", archive.path, "-C", directory.path]
        if let password, !password.isEmpty {
            arguments += ["--passphrase", password]
        }

        let result = try await ProcessRunner.run(executable, arguments: arguments)
        if result.wasCancelled { throw ExtractionError.cancelled }
        guard result.exitCode == 0 else {
            let stderr = result.stderr
            if stderr.localizedCaseInsensitiveContains("passphrase") || stderr.localizedCaseInsensitiveContains("encrypted") {
                throw (password ?? "").isEmpty ? ExtractionError.passwordRequired : ExtractionError.wrongPassword
            }
            if stderr.localizedCaseInsensitiveContains("unrecognized archive format") {
                throw ExtractionError.notAnArchive
            }
            throw ExtractionError.failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        progress(1)
    }
}
