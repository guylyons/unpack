import Foundation

/// A backend that knows how to expand an archive into a directory.
protocol ArchiveEngine: Sendable {
    var displayName: String { get }

    /// Extracts `archive` into `directory` (which already exists).
    /// `progress` is called with 0…1 whenever the engine knows more.
    func extract(
        _ archive: URL,
        into directory: URL,
        password: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

enum ExtractionError: LocalizedError, Equatable {
    case passwordRequired
    case wrongPassword
    case notAnArchive
    case engineUnavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired: "This archive is password protected."
        case .wrongPassword: "That password didn't work."
        case .notAnArchive: "This doesn't look like an archive Unpack can open."
        case .engineUnavailable: "No extraction engine was found."
        case .cancelled: "Cancelled."
        case .failed(let message): message
        }
    }

    var needsPassword: Bool {
        self == .passwordRequired || self == .wrongPassword
    }
}

enum Engines {
    /// The best engine available: bundled 7-Zip, then a Homebrew 7-Zip, then
    /// the libarchive `bsdtar` that ships with macOS.
    static func preferred() -> any ArchiveEngine {
        if let sevenZip = SevenZipEngine.locate() { return sevenZip }
        return LibarchiveEngine()
    }
}
