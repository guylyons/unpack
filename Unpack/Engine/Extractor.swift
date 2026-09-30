import Foundation

/// Turns "an archive" into "a tidy folder next to it".
///
/// Everything is expanded into a hidden staging folder in the destination
/// first, so a failed or cancelled run never leaves half an archive behind,
/// and so we can look at what came out before deciding where it goes.
struct Extractor: Sendable {
    struct Options: Sendable {
        /// If the archive holds exactly one item, put it straight in the
        /// destination instead of wrapping it in a folder.
        var skipWrapperFolder = true
        /// Unpack "foo.tar" automatically after un-gzipping "foo.tar.gz".
        var expandNestedTarballs = true
    }

    var engine: any ArchiveEngine
    var options = Options()

    private static let junk: Set<String> = ["__MACOSX", ".DS_Store"]

    /// Returns the URL of what was created: a folder, or the single item.
    func extract(
        _ archive: URL,
        to destination: URL,
        password: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let staging = destination.appendingPathComponent(".unpack-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try await engine.extract(archive, into: staging, password: password, progress: progress)
        try Task.checkCancellation()

        if options.expandNestedTarballs {
            try await expandInnerTarball(in: staging, password: password)
        }

        var contents = try visibleContents(of: staging)
        if contents.isEmpty {
            throw ExtractionError.failed("The archive is empty.")
        }

        if options.skipWrapperFolder, contents.count == 1 {
            let item = contents.removeFirst()
            let target = ArchiveNaming.uniqueURL(for: item.lastPathComponent, in: destination)
            try fm.moveItem(at: item, to: target)
            return target
        }

        let target = ArchiveNaming.uniqueURL(for: ArchiveNaming.baseName(for: archive), in: destination)
        try fm.moveItem(at: staging, to: target)
        return target
    }

    /// "foo.tar.gz" decompresses to a lone "foo.tar"; unpack that too.
    private func expandInnerTarball(in staging: URL, password: String?) async throws {
        let contents = try visibleContents(of: staging)
        guard contents.count == 1,
              let tarball = contents.first,
              tarball.pathExtension.lowercased() == "tar"
        else { return }

        let inner = staging.appendingPathComponent(".tar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try await engine.extract(tarball, into: inner, password: password) { _ in }

        try FileManager.default.removeItem(at: tarball)
        for item in try visibleContents(of: inner) {
            try FileManager.default.moveItem(at: item, to: staging.appendingPathComponent(item.lastPathComponent))
        }
        try FileManager.default.removeItem(at: inner)
    }

    private func visibleContents(of directory: URL) throws -> [URL] {
        let fm = FileManager.default
        var items: [URL] = []
        for name in try fm.contentsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(name)
            if Self.junk.contains(name) {
                try? fm.removeItem(at: url)
            } else {
                items.append(url)
            }
        }
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
