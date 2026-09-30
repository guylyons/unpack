import Foundation
import Observation

@MainActor
@Observable
final class ExtractionJob: Identifiable {
    enum State: Equatable {
        case waiting
        case extracting
        case needsPassword(retry: Bool)
        case finished(URL)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let archive: URL
    let destination: URL
    var state: State = .waiting
    /// nil while the engine hasn't reported anything (shows an indeterminate bar).
    var progress: Double?
    var password: String?

    @ObservationIgnored var task: Task<Void, Never>?

    init(archive: URL, destination: URL) {
        self.archive = archive
        self.destination = destination
    }

    var name: String { archive.lastPathComponent }

    var formatLabel: String {
        let lower = archive.lastPathComponent.lowercased()
        if lower.firstMatch(of: #/\.part\d+\.rar$/#) != nil { return "RAR" }
        if lower.firstMatch(of: #/\.tar\.[a-z0-9]+$/#) != nil { return "TAR" }
        let ext = archive.pathExtension
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    var isActive: Bool {
        switch state {
        case .waiting, .extracting, .needsPassword: true
        default: false
        }
    }

    var isDone: Bool {
        if case .finished = state { return true }
        return false
    }
}
