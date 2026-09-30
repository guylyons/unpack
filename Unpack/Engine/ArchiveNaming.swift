import Foundation

/// Filename rules: what to call the output folder, and which files in a
/// multi-volume set are the ones you actually open.
enum ArchiveNaming {
    /// Extensions that are a compressed tarball on their own ("foo.tgz").
    static let tarballShorthands: Set<String> = ["tgz", "tbz", "tbz2", "txz", "tlz", "tzst", "taz", "tpz"]

    /// Compression wrappers that commonly sit on top of ".tar".
    static let tarWrappers: Set<String> = ["gz", "bz2", "xz", "lzma", "zst", "z", "lz", "lz4"]

    /// "Photos.tar.gz" → "Photos", "Game.part01.rar" → "Game", "Backup.7z.001" → "Backup".
    static func baseName(for url: URL) -> String {
        var name = url.lastPathComponent
        let lower = name.lowercased()

        if let match = lower.firstMatch(of: #/\.part\d+\.rar$/#) {
            return String(name[..<match.range.lowerBound])
        }
        if let match = lower.firstMatch(of: #/\.[a-z0-9]+\.\d{3}$/#) {
            return String(name[..<match.range.lowerBound])
        }

        let ext = (name as NSString).pathExtension.lowercased()
        name = (name as NSString).deletingPathExtension
        if tarWrappers.contains(ext), (name as NSString).pathExtension.lowercased() == "tar" {
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? url.lastPathComponent : name
    }

    /// True for the 2nd+ file of a multi-volume set. These can't be opened on
    /// their own; extracting the first volume pulls them in automatically.
    static func isContinuationVolume(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()

        // Game.part2.rar, Game.part02.rar …
        if let match = lower.firstMatch(of: #/\.part(\d+)\.rar$/#), let n = Int(match.1) {
            return n > 1
        }
        // Old-style RAR: Game.rar, Game.r00, Game.r01 …
        if lower.firstMatch(of: #/\.r\d{2}$/#) != nil { return true }
        // Split zip: Game.z01, Game.z02 … Game.zip (the .zip is the entry point)
        if lower.firstMatch(of: #/\.z\d{2}$/#) != nil { return true }
        // Generic splits: Backup.7z.001, Backup.7z.002 …
        if let match = lower.firstMatch(of: #/\.(\d{3})$/#), let n = Int(match.1) {
            return n > 1
        }
        return false
    }

    /// Every file on disk that belongs to the same volume set as `url`
    /// (including `url` itself), so they can all be tidied up together.
    static func volumeSet(for url: URL, fileManager: FileManager = .default) -> [URL] {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let lower = name.lowercased()

        let pattern: Regex<AnyRegexOutput>
        if let match = lower.firstMatch(of: #/\.part\d+\.rar$/#) {
            let stem = NSRegularExpression.escapedPattern(for: String(lower[..<match.range.lowerBound]))
            pattern = try! Regex("^\(stem)\\.part\\d+\\.rar$")
        } else if let match = lower.firstMatch(of: #/\.\d{3}$/#) {
            let stem = NSRegularExpression.escapedPattern(for: String(lower[..<match.range.lowerBound]))
            pattern = try! Regex("^\(stem)\\.\\d{3}$")
        } else if lower.hasSuffix(".rar") {
            let stem = NSRegularExpression.escapedPattern(for: String(lower.dropLast(4)))
            pattern = try! Regex("^\(stem)\\.(rar|r\\d{2})$")
        } else if lower.hasSuffix(".zip") {
            let stem = NSRegularExpression.escapedPattern(for: String(lower.dropLast(4)))
            pattern = try! Regex("^\(stem)\\.(zip|z\\d{2})$")
        } else {
            return [url]
        }

        let siblings = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
        let matches = siblings
            .filter { $0.lowercased().wholeMatch(of: pattern) != nil }
            .sorted()
            .map { dir.appendingPathComponent($0) }
        return matches.isEmpty ? [url] : matches
    }

    /// Finder-style de-duplication: "Photos", "Photos 2", "Photos 3" …
    /// Keeps the extension on files ("notes 2.txt").
    static func uniqueURL(for name: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let numbered = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let url = directory.appendingPathComponent(numbered)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
