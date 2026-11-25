import Foundation

final class PersistenceStore {
    static let shared = PersistenceStore()

    private let directoryURL: URL
    private let storesURL: URL
    private let settingsURL: URL
    private let liveThemesURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = appSupport.appendingPathComponent("Storefront", isDirectory: true)
        storesURL = directoryURL.appendingPathComponent("stores.json")
        settingsURL = directoryURL.appendingPathComponent("settings.json")
        liveThemesURL = directoryURL.appendingPathComponent("live-themes.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func loadStores() -> [Store] {
        guard let data = try? Data(contentsOf: storesURL) else {
            return []
        }
        return (try? JSONDecoder().decode([Store].self, from: data)) ?? []
    }

    func save(stores: [Store]) {
        guard let data = try? JSONEncoder().encode(stores) else { return }
        try? data.write(to: storesURL, options: .atomic)
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    /// Last known live theme per myshopify domain, so a reopened panel can show every
    /// store's theme at once instead of waiting for the Shopify CLI to reach it.
    func loadLiveThemes() -> [String: CachedLiveTheme] {
        guard let data = try? Data(contentsOf: liveThemesURL) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedLiveTheme].self, from: data)) ?? [:]
    }

    func save(liveThemes: [String: CachedLiveTheme]) {
        guard let data = try? JSONEncoder().encode(liveThemes) else { return }
        try? data.write(to: liveThemesURL, options: .atomic)
    }
}

struct CachedLiveTheme: Codable, Equatable {
    let theme: ShopifyCLI.RemoteTheme
    let fetchedAt: Date
}
