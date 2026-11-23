import Foundation

/// Builds through 0.0.19 ran in the App Sandbox, so their stores, settings, favicons and
/// defaults live in `~/Library/Containers/<bundle id>/Data`. The sandbox came off so
/// "Sync from Shopify" can run the Shopify CLI, which moves every path back to the real
/// `~/Library`. This copies the old data across once, before anything reads it.
enum SandboxMigration {
    private static let doneKey = "SandboxMigration.didCopyContainerData"

    static func runIfNeeded(fileManager: FileManager = .default) {
        // Still sandboxed (say, an old build): the paths already point at the container.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let containerLibrary = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library", isDirectory: true)
        guard fileManager.fileExists(atPath: containerLibrary.path) else { return }

        copyApplicationSupport(from: containerLibrary, fileManager: fileManager)
        copyDefaults(from: containerLibrary, bundleID: bundleID, into: defaults)
    }

    /// Copies each item the new folder doesn't have yet. `PersistenceStore` and
    /// `FaviconStore` create empty folders on init, so the folder alone may already exist.
    private static func copyApplicationSupport(from containerLibrary: URL, fileManager: FileManager) {
        let source = containerLibrary.appendingPathComponent("Application Support/Storefront", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil),
              !items.isEmpty else { return }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let destination = appSupport.appendingPathComponent("Storefront", isDirectory: true)
        // A real store list here means this Mac already ran an unsandboxed build: leave it.
        guard !fileManager.fileExists(atPath: destination.appendingPathComponent("stores.json").path) else { return }
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                // Only an empty folder made by an init is safe to replace.
                let contents = (try? fileManager.contentsOfDirectory(atPath: target.path)) ?? ["keep"]
                guard contents.isEmpty else { continue }
                try? fileManager.removeItem(at: target)
            }
            try? fileManager.copyItem(at: item, to: target)
        }
    }

    /// Sparkle's update preferences and the status item position live in defaults.
    private static func copyDefaults(from containerLibrary: URL, bundleID: String, into defaults: UserDefaults) {
        let plist = containerLibrary.appendingPathComponent("Preferences/\(bundleID).plist")
        guard let values = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
