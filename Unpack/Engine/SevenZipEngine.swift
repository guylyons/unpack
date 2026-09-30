import Foundation

/// Extracts with the 7-Zip console binary (`7zz`): RAR/RAR5, 7z, zip, tar,
/// gzip, bzip2, xz, zstd, ISO, DMG, CAB, LZH, ARJ, and many more.
struct SevenZipEngine: ArchiveEngine {
    let executable: URL

    var displayName: String { "7-Zip" }

    /// The copy bundled in Unpack.app/Contents/MacOS, else a Homebrew install.
    static func locate() -> SevenZipEngine? {
        let candidates = [
            Bundle.main.url(forAuxiliaryExecutable: "7zz"),
            URL(filePath: "/opt/homebrew/bin/7zz"),
            URL(filePath: "/usr/local/bin/7zz"),
        ]
        return candidates
            .compactMap { $0 }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            .map(SevenZipEngine.init(executable:))
    }

    func extract(
        _ archive: URL,
        into directory: URL,
        password: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let arguments = [
            "x",                          // extract with full paths
            "-y",                         // assume yes to every prompt
            "-bsp1", "-bso0", "-bse2",    // progress → stdout, messages off, errors → stderr
            "-aou",                       // rename on name clashes inside the archive
            "-p\(password ?? "")",        // an explicit (possibly empty) password never prompts
            "-o\(directory.path)",
            "--",
            archive.path,
        ]

        let parser = ProgressState()
        let result = try await ProcessRunner.run(executable, arguments: arguments) { chunk in
            if let value = parser.consume(chunk) { progress(value) }
        }

        if result.wasCancelled { throw ExtractionError.cancelled }
        // 1 = warnings only (e.g. a file couldn't have its date set) — the files are there.
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw SevenZipOutput.classifyFailure(
                exitCode: result.exitCode,
                stderr: result.stderr,
                passwordSupplied: !(password ?? "").isEmpty
            )
        }
        progress(1)
    }
}

private final class ProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = SevenZipProgressParser()

    func consume(_ chunk: String) -> Double? {
        lock.withLock { parser.consume(chunk) }
    }
}
