import SwiftUI

struct JobList: View {
    var namespace: Namespace.ID
    @Environment(JobQueue.self) private var queue

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(queue.jobs) { job in
                    JobRow(job: job)
                        .glassEffectID(job.id, in: namespace)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
    }
}

struct JobRow: View {
    let job: ExtractionJob
    @Environment(JobQueue.self) private var queue

    var body: some View {
        HStack(spacing: 12) {
            Text(job.formatLabel)
                .font(.caption2.weight(.bold).monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(tint.opacity(0.45)), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .contextMenu {
            Button("Show Archive in Finder") { NSWorkspace.shared.activateFileViewerSelecting([job.archive]) }
            Button("Remove from List") { withAnimation { queue.remove(job) } }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .waiting:
            caption("Waiting…")
        case .extracting:
            if let progress = job.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        case .needsPassword(let retry):
            caption(retry ? "Wrong password" : "Needs a password", systemImage: "lock.fill", color: .orange)
        case .finished(let url):
            caption("Unpacked to \(url.lastPathComponent)", systemImage: "checkmark.circle.fill", color: .green)
        case .failed(let message):
            caption(message, systemImage: "exclamationmark.triangle.fill", color: .red)
                .help(message)
        case .cancelled:
            caption("Cancelled", systemImage: "xmark.circle", color: .secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .waiting, .extracting:
                iconButton("Cancel", systemImage: "xmark") { queue.cancel(job) }
            case .needsPassword:
                iconButton("Enter Password", systemImage: "key.fill") { queue.passwordPrompt = job }
            case .finished:
                iconButton("Show in Finder", systemImage: "magnifyingglass") { queue.reveal(job) }
            case .failed, .cancelled:
                iconButton("Try Again", systemImage: "arrow.clockwise") { queue.retry(job) }
            }
        }
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(title)
    }

    private func caption(_ text: String, systemImage: String? = nil, color: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(color)
            }
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }

    private var tint: Color {
        switch job.state {
        case .finished: .green
        case .failed: .red
        case .needsPassword: .orange
        case .cancelled: .gray
        default: .accentColor
        }
    }
}
