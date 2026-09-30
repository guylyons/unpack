import AppKit
import Observation

/// Everything the window shows: the list of jobs, and which one (if any) is
/// waiting on a password. Runs a couple of extractions at a time.
@MainActor
@Observable
final class JobQueue {
    private(set) var jobs: [ExtractionJob] = []

    /// The job the password sheet is asking about.
    var passwordPrompt: ExtractionJob?

    let engine: any ArchiveEngine
    private let maxConcurrent = 2
    /// Passwords that worked this session, tried automatically on the next
    /// locked archive (handy for a batch of archives sharing one password).
    private var knownPasswords: [String] = []
    private var revealQueue: [URL] = []
    private var batchHadFailures = false

    init(engine: any ArchiveEngine = Engines.preferred()) {
        self.engine = engine
    }

    var hasFinishedJobs: Bool { jobs.contains { !$0.isActive } }
    var isBusy: Bool { jobs.contains { $0.isActive } }

    // MARK: Adding

    func add(_ urls: [URL]) {
        let archives = urls
            .filter { !$0.hasDirectoryPath }
            .filter { !ArchiveNaming.isContinuationVolume($0) }
            .filter { url in !jobs.contains { $0.isActive && $0.archive == url } }
        guard !archives.isEmpty else { return }

        let destination: URL?
        switch Preferences.mode {
        case .besideArchive: destination = nil
        case .fixedFolder: destination = Preferences.fixedFolder
        case .ask:
            guard let chosen = Self.askForDestination(near: archives[0]) else { return }
            destination = chosen
        }

        for archive in archives {
            let target = destination ?? Self.writableFolder(beside: archive)
            jobs.insert(ExtractionJob(archive: archive, destination: target), at: 0)
        }
        pump()
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose archives to unpack"
        panel.prompt = "Unpack"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    // MARK: Job actions

    func cancel(_ job: ExtractionJob) {
        job.task?.cancel()
        if case .waiting = job.state { job.state = .cancelled }
        if case .needsPassword = job.state { job.state = .cancelled }
        if passwordPrompt === job { passwordPrompt = nextPasswordPrompt() }
        pump()
    }

    func retry(_ job: ExtractionJob) {
        job.state = .waiting
        job.progress = nil
        pump()
    }

    func submitPassword(_ password: String, for job: ExtractionJob) {
        job.password = password
        passwordPrompt = nil
        retry(job)
    }

    func skipPassword(for job: ExtractionJob) {
        job.state = .cancelled
        passwordPrompt = nextPasswordPrompt()
        pump()
    }

    func remove(_ job: ExtractionJob) {
        job.task?.cancel()
        jobs.removeAll { $0 === job }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive }
    }

    func reveal(_ job: ExtractionJob) {
        if case .finished(let url) = job.state {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([job.archive])
        }
    }

    // MARK: Running

    private func pump() {
        let running = jobs.filter { $0.state == .extracting }.count
        let waiting = jobs.filter { $0.state == .waiting }.reversed()   // oldest first
        for job in waiting.prefix(max(0, maxConcurrent - running)) {
            start(job)
        }
        if !isBusy { batchFinished() }
    }

    private func start(_ job: ExtractionJob) {
        job.state = .extracting
        job.progress = nil

        let extractor = Extractor(
            engine: engine,
            options: .init(skipWrapperFolder: Preferences.bool(Preferences.skipWrapperFolder))
        )
        let candidates = job.password.map { [$0] } ?? [nil] + knownPasswords.reversed().map(Optional.some)

        job.task = Task { [weak self] in
            var outcome: Result<URL, Error> = .failure(ExtractionError.passwordRequired)
            for password in candidates {
                do {
                    let url = try await extractor.extract(job.archive, to: job.destination, password: password) { value in
                        Task { @MainActor in job.progress = value }
                    }
                    if let password, !password.isEmpty { self?.remember(password) }
                    outcome = .success(url)
                    break
                } catch let error as ExtractionError where error.needsPassword && !Task.isCancelled {
                    outcome = .failure(error)
                    continue
                } catch {
                    outcome = .failure(error)
                    break
                }
            }
            self?.finish(job, with: outcome)
        }
    }

    private func finish(_ job: ExtractionJob, with outcome: Result<URL, Error>) {
        job.task = nil
        switch outcome {
        case .success(let url):
            job.state = .finished(url)
            job.progress = 1
            revealQueue.append(url)
            if Preferences.bool(Preferences.trashArchiveWhenDone) {
                NSWorkspace.shared.recycle(ArchiveNaming.volumeSet(for: job.archive))
            }
        case .failure(let error as ExtractionError) where error == .cancelled:
            job.state = .cancelled
        case .failure(_) where Task.isCancelled:
            job.state = .cancelled
        case .failure(let error as ExtractionError) where error.needsPassword:
            job.state = .needsPassword(retry: job.password != nil)
            if passwordPrompt == nil { passwordPrompt = job }
        case .failure(let error):
            job.state = .failed(error.localizedDescription)
            batchHadFailures = true
        }
        pump()
    }

    private func remember(_ password: String) {
        knownPasswords.removeAll { $0 == password }
        knownPasswords.append(password)
    }

    private func nextPasswordPrompt() -> ExtractionJob? {
        jobs.last { if case .needsPassword = $0.state { true } else { false } }
    }

    private func batchFinished() {
        defer {
            revealQueue.removeAll()
            batchHadFailures = false
        }
        guard !revealQueue.isEmpty else { return }
        if Preferences.bool(Preferences.revealWhenDone) {
            NSWorkspace.shared.activateFileViewerSelecting(revealQueue)
        }
        if Preferences.bool(Preferences.quitWhenDone), !batchHadFailures {
            NSApp.terminate(nil)
        }
    }

    // MARK: Destinations

    /// The archive's own folder, or Downloads if that folder is read-only
    /// (a mounted disk image, a network share, …).
    static func writableFolder(beside archive: URL) -> URL {
        let parent = archive.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path) ? parent : .downloadsDirectory
    }

    private static func askForDestination(near archive: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Unpack to…"
        panel.prompt = "Unpack Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = archive.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
