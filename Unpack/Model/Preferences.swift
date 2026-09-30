import Foundation

enum DestinationMode: String, CaseIterable, Identifiable {
    case besideArchive
    case fixedFolder
    case ask

    var id: Self { self }

    var title: String {
        switch self {
        case .besideArchive: "Next to the archive"
        case .fixedFolder: "In a folder I choose"
        case .ask: "Ask every time"
        }
    }
}

/// UserDefaults keys and defaults, shared by `@AppStorage` in views and the job queue.
enum Preferences {
    static let destinationMode = "destinationMode"
    static let fixedFolderPath = "fixedFolderPath"
    static let skipWrapperFolder = "skipWrapperFolder"
    static let revealWhenDone = "revealWhenDone"
    static let trashArchiveWhenDone = "trashArchiveWhenDone"
    static let quitWhenDone = "quitWhenDone"

    static func register() {
        UserDefaults.standard.register(defaults: [
            destinationMode: DestinationMode.besideArchive.rawValue,
            fixedFolderPath: URL.downloadsDirectory.path,
            skipWrapperFolder: true,
            revealWhenDone: true,
            trashArchiveWhenDone: false,
            quitWhenDone: false,
        ])
    }

    static var mode: DestinationMode {
        DestinationMode(rawValue: UserDefaults.standard.string(forKey: destinationMode) ?? "") ?? .besideArchive
    }

    static var fixedFolder: URL {
        URL(filePath: UserDefaults.standard.string(forKey: fixedFolderPath) ?? URL.downloadsDirectory.path)
    }

    static func bool(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
