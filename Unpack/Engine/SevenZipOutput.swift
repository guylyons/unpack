import Foundation

/// Reads 7-Zip's console output.
///
/// With `-bsp1`, progress lands on stdout as frames like `" 45% 12 - photo.jpg"`
/// that are erased with backspaces, so a frame boundary is a `\b`, `\r` or `\n`.
struct SevenZipProgressParser {
    private var buffer = ""

    /// Feed raw stdout; returns the latest percentage seen (0…1), if any.
    mutating func consume(_ chunk: String) -> Double? {
        buffer += chunk
        let frames = buffer.split(omittingEmptySubsequences: false) { $0 == "\u{8}" || $0 == "\r" || $0 == "\n" }
        buffer = String(frames.last ?? "")

        var latest: Double?
        for frame in frames.dropLast() {
            if let percent = Self.percent(in: frame) { latest = percent }
        }
        return latest
    }

    static func percent(in frame: Substring) -> Double? {
        guard let match = frame.firstMatch(of: #/(\d{1,3})%/#), let value = Int(match.1), value <= 100 else {
            return nil
        }
        return Double(value) / 100
    }
}

enum SevenZipOutput {
    /// Maps a failed run to the error the user should see.
    static func classifyFailure(exitCode: Int32, stderr: String, passwordSupplied: Bool) -> ExtractionError {
        if stderr.localizedCaseInsensitiveContains("wrong password")
            || stderr.localizedCaseInsensitiveContains("encrypted archive") {
            return passwordSupplied ? .wrongPassword : .passwordRequired
        }
        if stderr.localizedCaseInsensitiveContains("cannot open the file as archive")
            || stderr.localizedCaseInsensitiveContains("can not open the file as archive")
            || stderr.localizedCaseInsensitiveContains("is not archive") {
            return .notAnArchive
        }
        if exitCode == 255 { return .cancelled }

        let detail = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("ERROR:") }
            ?? stderr.split(whereSeparator: \.isNewline).first.map(String.init)
            ?? "7-Zip stopped with exit code \(exitCode)."
        return .failed(detail)
    }
}
