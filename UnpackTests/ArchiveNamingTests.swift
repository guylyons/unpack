import Foundation
import Testing
@testable import Unpack

struct ArchiveNamingTests {
    @Test(arguments: [
        ("Photos.zip", "Photos"),
        ("Photos.tar.gz", "Photos"),
        ("Photos.tar.bz2", "Photos"),
        ("Photos.tgz", "Photos"),
        ("notes.txt.gz", "notes.txt"),
        ("Game.part01.rar", "Game"),
        ("Game.part1.rar", "Game"),
        ("Backup.7z.001", "Backup"),
        ("Backup.001", "Backup"),
        ("my.dotted.name.rar", "my.dotted.name"),
        ("README", "README"),
    ])
    func baseName(file: String, expected: String) {
        #expect(ArchiveNaming.baseName(for: URL(filePath: "/tmp/\(file)")) == expected)
    }

    @Test(arguments: [
        ("Game.part1.rar", false),
        ("Game.part01.rar", false),
        ("Game.part2.rar", true),
        ("Game.part10.rar", true),
        ("Game.rar", false),
        ("Game.r00", true),
        ("Game.r15", true),
        ("Split.zip", false),
        ("Split.z01", true),
        ("Backup.7z.001", false),
        ("Backup.7z.002", true),
        ("Photos.zip", false),
    ])
    func continuationVolumes(file: String, isContinuation: Bool) {
        #expect(ArchiveNaming.isContinuationVolume(URL(filePath: "/tmp/\(file)")) == isContinuation)
    }

    @Test func uniqueURLAddsFinderStyleNumbers() throws {
        let dir = try TemporaryDirectory()
        let fm = FileManager.default

        #expect(ArchiveNaming.uniqueURL(for: "Photos", in: dir.url).lastPathComponent == "Photos")
        try fm.createDirectory(at: dir.url.appendingPathComponent("Photos"), withIntermediateDirectories: false)
        #expect(ArchiveNaming.uniqueURL(for: "Photos", in: dir.url).lastPathComponent == "Photos 2")
        try fm.createDirectory(at: dir.url.appendingPathComponent("Photos 2"), withIntermediateDirectories: false)
        #expect(ArchiveNaming.uniqueURL(for: "Photos", in: dir.url).lastPathComponent == "Photos 3")

        fm.createFile(atPath: dir.url.appendingPathComponent("notes.txt").path, contents: Data())
        #expect(ArchiveNaming.uniqueURL(for: "notes.txt", in: dir.url).lastPathComponent == "notes 2.txt")
    }

    @Test func volumeSetFindsSiblings() throws {
        let dir = try TemporaryDirectory()
        for name in ["Game.part1.rar", "Game.part2.rar", "Game.part3.rar", "Other.part1.rar", "Game.nfo"] {
            FileManager.default.createFile(atPath: dir.url.appendingPathComponent(name).path, contents: Data())
        }
        let set = ArchiveNaming.volumeSet(for: dir.url.appendingPathComponent("Game.part1.rar"))
        #expect(set.map(\.lastPathComponent) == ["Game.part1.rar", "Game.part2.rar", "Game.part3.rar"])

        let single = dir.url.appendingPathComponent("Game.nfo")
        #expect(ArchiveNaming.volumeSet(for: single) == [single])
    }
}

struct SevenZipOutputTests {
    @Test func parsesBackspaceSeparatedProgressFrames() {
        var parser = SevenZipProgressParser()
        #expect(parser.consume("  0M Scan\u{8}\u{8}\u{8}") == nil)
        #expect(parser.consume("  0%\u{8}\u{8}\u{8}\u{8} 45% 3 - big.bin\u{8}\u{8}") == 0.45)
        // A frame split across two reads is stitched back together.
        #expect(parser.consume(" 8") == nil)
        #expect(parser.consume("7% 4\u{8}") == 0.87)
        #expect(parser.consume("\r100%\n") == 1.0)
    }

    @Test func classifiesPasswordErrors() {
        let stderr = "ERROR: enc.7z\nCannot open encrypted archive. Wrong password?\n"
        #expect(SevenZipOutput.classifyFailure(exitCode: 2, stderr: stderr, passwordSupplied: false) == .passwordRequired)
        #expect(SevenZipOutput.classifyFailure(exitCode: 2, stderr: stderr, passwordSupplied: true) == .wrongPassword)
        let zip = "ERROR: Wrong password : src/big.bin\n"
        #expect(SevenZipOutput.classifyFailure(exitCode: 2, stderr: zip, passwordSupplied: false) == .passwordRequired)
    }

    @Test func classifiesNonArchives() {
        let stderr = "ERROR: notes.txt\nnotes.txt\nCannot open the file as archive\n"
        #expect(SevenZipOutput.classifyFailure(exitCode: 2, stderr: stderr, passwordSupplied: false) == .notAnArchive)
    }
}
