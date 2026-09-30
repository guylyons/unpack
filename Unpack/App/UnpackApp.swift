import SwiftUI

@main
struct UnpackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Preferences.register()
    }

    var body: some Scene {
        Window("Unpack", id: "main") {
            ContentView()
                .environment(appDelegate.queue)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 460, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Archives…") { appDelegate.queue.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView(engineName: appDelegate.queue.engine.displayName)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue = JobQueue()

    /// Files dropped on the Dock icon, or opened from Finder with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        queue.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
