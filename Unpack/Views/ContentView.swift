import SwiftUI

struct ContentView: View {
    @Environment(JobQueue.self) private var queue
    @State private var isTargeted = false
    @Namespace private var glass

    private var compact: Bool { !queue.jobs.isEmpty }

    var body: some View {
        @Bindable var queue = queue

        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 14) {
                DropZone(isTargeted: isTargeted, compact: compact) {
                    queue.presentOpenPanel()
                }
                .glassEffectID("dropzone", in: glass)

                if compact {
                    JobList(namespace: glass)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 6)
        }
        .frame(minWidth: 400, minHeight: compact ? 440 : 400)
        .background { Backdrop(isTargeted: isTargeted) }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls)
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { isTargeted = targeted }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: queue.jobs.map(\.id))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if queue.hasFinishedJobs {
                    Button("Clear Finished", systemImage: "checklist.checked") {
                        withAnimation { queue.clearFinished() }
                    }
                    .help("Remove finished items from the list")
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(item: $queue.passwordPrompt) { job in
            PasswordSheet(job: job)
        }
    }
}

/// Soft colour washes behind the glass, picked from the app icon.
private struct Backdrop: View {
    var isTargeted: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle()
                .fill(Color.orange.gradient)
                .frame(width: 360)
                .offset(x: -150, y: -170)
            Circle()
                .fill(Color.mint.gradient)
                .frame(width: 280)
                .offset(x: 170, y: -40)
            Circle()
                .fill(Color.purple.gradient)
                .frame(width: 300)
                .offset(x: -40, y: 230)
        }
        .blur(radius: 90)
        .opacity(colorScheme == .dark ? 0.45 : 0.55)
        .saturation(isTargeted ? 1.4 : 1)
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environment(JobQueue())
}
