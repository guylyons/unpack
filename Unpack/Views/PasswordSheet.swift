import SwiftUI

struct PasswordSheet: View {
    let job: ExtractionJob
    @Environment(JobQueue.self) private var queue
    @State private var password = ""
    @FocusState private var focused: Bool

    private var isRetry: Bool {
        if case .needsPassword(retry: true) = job.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .circle)

            VStack(spacing: 4) {
                Text("Password Required")
                    .font(.title3.weight(.semibold))
                Text("“\(job.name)” is encrypted.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)

            if isRetry {
                Label("That password didn't work. Try again.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Skip") { queue.skipPassword(for: job) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Unpack", action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        queue.submitPassword(password, for: job)
    }
}
