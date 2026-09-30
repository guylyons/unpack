import Foundation
import Testing
@testable import Unpack

/// End-to-end: build real archives with the bundled 7zz, then unpack them.
@Suite(.serialized)
struct ExtractorTests {
    let sevenZip: SevenZipEngine
    let dir: TemporaryDirectory

    init() throws {
        sevenZip = try #require(SevenZipEngine.locate(), "7zz should be bundled in Unpack.app")
        dir = try TemporaryDirectory()
    }

    /// A small tree: Project/readme.txt, Project/src/main.swift
    private func makeSource(named name: String = "Project") throws -> URL {
        let root = dir.url.appendingPathComponent("source/\(name)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "print(1)".write(to: root.appendingPathComponent("src/main.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private func sevenZip(_ args: [String], in cwd: URL) throws {
        let process = Process()
        process.executableURL = sevenZip.executable
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "7zz \(args.joined(separator: " "))")
    }

    private func randomData(_ count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(filePath: "/dev/urandom"))
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    private func out() throws -> URL {
        let url = dir.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func visible(_ url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    @Test func singleTopLevelFolderIsNotDoubleWrapped() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Download.zip")
        try sevenZip(["a", archive.path, source.lastPathComponent], in: source.deletingLastPathComponent())

        let result = try await Extractor(engine: sevenZip).extract(archive, to: try out(), password: nil) { _ in }

        #expect(result.lastPathComponent == "Project")
        #expect(try String(contentsOf: result.appendingPathComponent("readme.txt"), encoding: .utf8) == "hello")
        #expect(try visible(try out()) == ["Project"], "no staging folders left behind")
    }

    @Test func looseFilesGetAFolderNamedAfterTheArchive() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Loose.7z")
        try sevenZip(["a", archive.path, "readme.txt", "src"], in: source)

        let result = try await Extractor(engine: sevenZip).extract(archive, to: try out(), password: nil) { _ in }

        #expect(result.lastPathComponent == "Loose")
        #expect(try visible(result) == ["readme.txt", "src"])
    }

    @Test func existingNamesAreNotOverwritten() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Download.zip")
        try sevenZip(["a", archive.path, "Project"], in: source.deletingLastPathComponent())
        let extractor = Extractor(engine: sevenZip)

        _ = try await extractor.extract(archive, to: try out(), password: nil) { _ in }
        let second = try await extractor.extract(archive, to: try out(), password: nil) { _ in }

        #expect(second.lastPathComponent == "Project 2")
    }

    @Test func tarGzIsFullyUnpackedInOneGo() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Project.tar.gz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["czf", archive.path, "-C", source.deletingLastPathComponent().path, "Project"]
        try tar.run()
        tar.waitUntilExit()

        let result = try await Extractor(engine: sevenZip).extract(archive, to: try out(), password: nil) { _ in }

        #expect(result.lastPathComponent == "Project")
        #expect(try visible(result) == ["readme.txt", "src"])
    }

    @Test func encryptedArchiveAsksForPasswordThenSucceeds() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Secret.7z")
        try sevenZip(["a", "-pswordfish", "-mhe=on", archive.path, "Project"], in: source.deletingLastPathComponent())
        let extractor = Extractor(engine: sevenZip)

        await #expect(throws: ExtractionError.passwordRequired) {
            try await extractor.extract(archive, to: try out(), password: nil) { _ in }
        }
        await #expect(throws: ExtractionError.wrongPassword) {
            try await extractor.extract(archive, to: try out(), password: "nope") { _ in }
        }
        #expect(try visible(try out()).isEmpty, "failed attempts leave nothing behind")

        let result = try await extractor.extract(archive, to: try out(), password: "swordfish") { _ in }
        #expect(try String(contentsOf: result.appendingPathComponent("readme.txt"), encoding: .utf8) == "hello")
    }

    @Test func encryptedZipEntriesAskForPassword() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Secret.zip")
        try sevenZip(["a", "-pswordfish", archive.path, "Project"], in: source.deletingLastPathComponent())

        await #expect(throws: ExtractionError.passwordRequired) {
            try await Extractor(engine: sevenZip).extract(archive, to: try out(), password: nil) { _ in }
        }
    }

    @Test func notAnArchiveIsReportedClearly() async throws {
        let file = dir.url.appendingPathComponent("notes.txt")
        try "just text".write(to: file, atomically: true, encoding: .utf8)

        await #expect(throws: ExtractionError.notAnArchive) {
            try await Extractor(engine: sevenZip).extract(file, to: try out(), password: nil) { _ in }
        }
    }

    @Test func multiVolumeArchiveExtractsFromFirstPart() async throws {
        let source = try makeSource()
        let big = source.appendingPathComponent("big.bin")
        try randomData(300_000).write(to: big)
        let archive = dir.url.appendingPathComponent("Split.7z")
        try sevenZip(["a", "-v100k", archive.path, "Project"], in: source.deletingLastPathComponent())

        let first = dir.url.appendingPathComponent("Split.7z.001")
        #expect(ArchiveNaming.volumeSet(for: first).count >= 3)

        let result = try await Extractor(engine: sevenZip).extract(first, to: try out(), password: nil) { _ in }
        #expect(try Data(contentsOf: result.appendingPathComponent("big.bin")) == Data(contentsOf: big))
    }

    @Test func progressIsReported() async throws {
        let source = try makeSource()
        try randomData(20_000_000).write(to: source.appendingPathComponent("big.bin"))
        let archive = dir.url.appendingPathComponent("Big.7z")
        try sevenZip(["a", "-mx0", archive.path, "Project"], in: source.deletingLastPathComponent())

        let values = Values()
        _ = try await Extractor(engine: sevenZip).extract(archive, to: try out(), password: nil) { values.append($0) }

        #expect(values.all.last == 1.0)
        #expect(values.all == values.all.sorted(), "progress only moves forward")
    }

    @Test func cancellingStopsAndCleansUp() async throws {
        let source = try makeSource()
        // Random bytes don't compress, so this takes long enough to interrupt.
        try randomData(300_000_000).write(to: source.appendingPathComponent("big.bin"))
        let archive = dir.url.appendingPathComponent("Huge.7z")
        try sevenZip(["a", "-mx0", archive.path, "Project"], in: source.deletingLastPathComponent())
        let destination = try out()

        let (started, signal) = AsyncStream<Void>.makeStream()
        let extractor = Extractor(engine: sevenZip)
        let task = Task { [extractor, archive, destination] in
            try await extractor.extract(archive, to: destination, password: nil) { _ in signal.yield() }
        }
        for await _ in started { break }
        task.cancel()

        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty, "staging folder removed")
    }

    @Test func libarchiveFallbackUnpacksZip() async throws {
        let source = try makeSource()
        let archive = dir.url.appendingPathComponent("Fallback.zip")
        try sevenZip(["a", archive.path, "Project"], in: source.deletingLastPathComponent())

        let result = try await Extractor(engine: LibarchiveEngine()).extract(archive, to: try out(), password: nil) { _ in }

        #expect(result.lastPathComponent == "Project")
        #expect(try visible(result) == ["readme.txt", "src"])
    }
}

private final class Values: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func append(_ value: Double) { lock.withLock { values.append(value) } }
    var all: [Double] { lock.withLock { values } }
}
