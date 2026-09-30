import SwiftUI

struct SettingsView: View {
    var engineName: String

    @AppStorage(Preferences.destinationMode) private var mode = DestinationMode.besideArchive
    @AppStorage(Preferences.fixedFolderPath) private var fixedFolderPath = URL.downloadsDirectory.path
    @AppStorage(Preferences.skipWrapperFolder) private var skipWrapperFolder = true
    @AppStorage(Preferences.revealWhenDone) private var revealWhenDone = true
    @AppStorage(Preferences.trashArchiveWhenDone) private var trashArchiveWhenDone = false
    @AppStorage(Preferences.quitWhenDone) private var quitWhenDone = false

    var body: some View {
        Form {
            Section("Where to unpack") {
                Picker("Put files", selection: $mode) {
                    ForEach(DestinationMode.allCases) { Text($0.title).tag($0) }
                }
                if mode == .fixedFolder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(URL(filePath: fixedFolderPath).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                }
                Toggle("Skip the extra folder when an archive holds just one item", isOn: $skipWrapperFolder)
            }

            Section("When done") {
                Toggle("Show unpacked files in Finder", isOn: $revealWhenDone)
                Toggle("Move archive to the Trash", isOn: $trashArchiveWhenDone)
                Toggle("Quit Unpack", isOn: $quitWhenDone)
            }

            Section {
                LabeledContent("Engine", value: engineName)
            } footer: {
                Text("Extraction powered by 7-Zip by Igor Pavlov, licensed under the GNU LGPL with the unRAR restriction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(filePath: fixedFolderPath)
        if panel.runModal() == .OK, let url = panel.url {
            fixedFolderPath = url.path
        }
    }
}
