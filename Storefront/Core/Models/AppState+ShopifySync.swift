import Foundation
import Observation

/// Each store owns its observation scope: background loads do not redraw other stores.
@Observable
@MainActor
final class ShopifyThemeState {
    private(set) var theme: ShopifyCLI.RemoteTheme?
    private(set) var liveRow: LinkRow?
    private(set) var rows = StaticLinkCatalog.rows(for: .themes)
    var isLoading = false
    var lastAttempt: Date?
    var message: String?
    var needsSignIn = false

    func shouldLoad(at now: Date = Date(), force: Bool = false) -> Bool {
        guard !isLoading else { return false }
        guard !force, let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= (message == nil ? 300 : 30)
    }

    /// Rebuild navigation only when the actual live theme changes, not on hover,
    /// keyboard focus, loading-state changes, or a refresh returning the same theme.
    func updateTheme(_ theme: ShopifyCLI.RemoteTheme?) {
        guard self.theme != theme else { return }
        self.theme = theme
        liveRow = theme.map {
            LinkRow(
                id: "themes.theme.\($0.id)", title: $0.name,
                path: "/themes/\($0.id)/editor", iconName: "ThemeIcon",
                isLiveTheme: true
            )
        }
        var updated = StaticLinkCatalog.rows(for: .themes)
        if let liveRow, let libraryIndex = updated.firstIndex(where: { $0.id == "themes.library" }) {
            updated.insert(liveRow, at: libraryIndex + 1)
        }
        rows = updated
    }
}

extension AppState {
    /// Queues every store on widget open: the selected store first, then the visible rail
    /// stores in display order. Fetches stay one at a time on purpose. Each
    /// `shopify theme list` refreshes and rotates the CLI's shared sign-in token, so
    /// overlapping runs race on it, fail with a false "log in" error, and can sign the
    /// CLI out. The disk cache and `prioritizeShopifyTheme` hide the wait instead.
    func preloadShopifyThemes() {
        guard enabledSections.contains(.themes) else { return }
        let now = Date()
        for store in [selectedStore].compactMap({ $0 }) + visibleStores
        where themeState(for: store).shouldLoad(at: now) {
            enqueueShopifyTheme(store, first: false)
        }
        startShopifyThemeQueue()
    }

    /// Hovering or picking a store makes it the next fetch, so a store at the bottom of
    /// the rail doesn't wait behind every store above it.
    func prioritizeShopifyTheme(for store: Store) {
        guard enabledSections.contains(.themes), themeState(for: store).shouldLoad() else { return }
        enqueueShopifyTheme(store, first: true)
        startShopifyThemeQueue()
    }

    private func enqueueShopifyTheme(_ store: Store, first: Bool) {
        let domain = store.myshopifyDomain.lowercased()
        if let index = shopifyThemeQueue.firstIndex(where: { $0.myshopifyDomain.lowercased() == domain }) {
            guard first else { return }
            shopifyThemeQueue.remove(at: index)
        }
        if first {
            shopifyThemeQueue.insert(store, at: 0)
        } else {
            shopifyThemeQueue.append(store)
        }
    }

    private func startShopifyThemeQueue() {
        guard shopifyThemePreloadTask == nil, !shopifyThemeQueue.isEmpty else { return }
        shopifyThemePreloadTask = Task {
            defer { shopifyThemePreloadTask = nil }
            while !shopifyThemeQueue.isEmpty {
                guard enabledSections.contains(.themes) else {
                    shopifyThemeQueue.removeAll()
                    break
                }
                await loadShopifyThemes(for: shopifyThemeQueue.removeFirst())
            }
        }
    }

    func themeState(for store: Store) -> ShopifyThemeState {
        let domain = store.myshopifyDomain.lowercased()
        if let state = shopifyThemes[domain] { return state }
        let state = ShopifyThemeState()
        if let cached = cachedLiveThemes[domain] {
            // Shown at once; still refreshed once older than the five-minute window.
            state.updateTheme(cached.theme)
            state.lastAttempt = cached.fetchedAt
        }
        shopifyThemes[domain] = state
        return state
    }

    /// UI and keyboard navigation must use the same list, including fetched themes.
    func linkRows(for section: SectionID, store: Store?) -> [LinkRow] {
        guard section == .themes, let store else { return StaticLinkCatalog.rows(for: section) }
        return themeState(for: store).rows
    }

    /// Refresh during widget preloading after five minutes, or immediately on explicit retry.
    /// A short failure cooldown avoids repeated CLI launches while switching stores.
    func loadShopifyThemes(for store: Store, force: Bool = false) async {
        let domain = store.myshopifyDomain.lowercased()
        let state = themeState(for: store)
        guard state.shouldLoad(force: force) else { return }
        state.isLoading = true
        state.message = nil
        state.needsSignIn = false

        var loadedTheme = state.theme
        do {
            loadedTheme = try await ShopifyCLI.fetchLiveTheme(for: domain)
            cachedLiveThemes[domain] = loadedTheme.map { CachedLiveTheme(theme: $0, fetchedAt: Date()) }
            saveLiveThemes()
        } catch ShopifyCLI.Failure.notInstalled {
            state.message = "Install Shopify CLI to load the live theme"
        } catch ShopifyCLI.Failure.notSignedIn(let message) {
            state.needsSignIn = true
            state.message = "Sign in to authorize live theme access for this store\n\n\(message)"
        } catch ShopifyCLI.Failure.failed(let message) {
            state.message = message
        } catch {
            state.message = error.localizedDescription
        }

        // Resolve focus after the await: the user may have navigated in the meantime.
        let isFocusedStore = selectedStore?.myshopifyDomain.lowercased() == domain
        let isThemesFocused = focusArea == .cards
            && enabledSections.indices.contains(focusedSectionIndex)
            && enabledSections[focusedSectionIndex] == .themes
        let preservesFocus = isFocusedStore && isThemesFocused
        let focusedID = preservesFocus && state.rows.indices.contains(focusedRowIndex)
            ? state.rows[focusedRowIndex].id : nil
        state.updateTheme(loadedTheme)
        state.isLoading = false
        state.lastAttempt = Date()
        if preservesFocus {
            focusedRowIndex = state.rows.firstIndex { $0.id == focusedID } ?? 0
        }
    }

    func signInForShopifyTheme(for store: Store) async {
        do {
            try await ShopifyCLI.openThemeSignInInTerminal(for: store.myshopifyDomain)
        } catch {
            let message: String
            if case ShopifyCLI.Failure.failed(let detail) = error {
                message = detail
            } else {
                message = error.localizedDescription
            }
            themeState(for: store).message = message
        }
    }
}

/// What the last sync brought in, kept for this session so Settings can point at the
/// new arrivals.
struct ShopifySyncSummary: Equatable {
    let addedIDs: [Store.ID]
    /// Stores Shopify returned that were already in the list (left untouched).
    let matchedCount: Int
}

enum ShopifySyncStatus: Equatable {
    case idle
    case syncing
    case synced(ShopifySyncSummary)
    case needsSignIn
    case notInstalled
    case failed(String)
}

/// The last successful sync, persisted so Settings can say when it happened.
struct ShopifySyncRecord: Codable, Equatable {
    let date: Date
    let storeCount: Int
    let organizationNames: [String]

    private static let defaultsKey = "ShopifySync.lastRecord"

    static func load() -> ShopifySyncRecord? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ShopifySyncRecord.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

extension AppState {
    var isSyncingShopify: Bool {
        shopifySyncStatus == .syncing
    }

    /// IDs the last sync added that still exist (some may have been deleted since).
    var recentlySyncedStoreIDs: Set<Store.ID> {
        guard case .synced(let summary) = shopifySyncStatus else { return [] }
        let existing = Set(stores.map(\.id))
        return Set(summary.addedIDs).intersection(existing)
    }

    /// Pulls every store the Shopify CLI account can reach and merges it into the list.
    func syncShopifyStores() {
        guard !isSyncingShopify else { return }
        shopifySyncStatus = .syncing
        Task {
            do {
                let snapshot = try await ShopifyCLI.fetchStores()
                let summary = mergeShopifyStores(snapshot.stores)
                let record = ShopifySyncRecord(
                    date: Date(),
                    storeCount: snapshot.stores.count,
                    organizationNames: snapshot.organizations.map(\.name)
                )
                record.save()
                lastShopifySync = record
                shopifySyncStatus = .synced(summary)
            } catch ShopifyCLI.Failure.notInstalled {
                shopifySyncStatus = .notInstalled
            } catch ShopifyCLI.Failure.notSignedIn {
                shopifySyncStatus = .needsSignIn
            } catch ShopifyCLI.Failure.failed(let message) {
                shopifySyncStatus = .failed(message)
            } catch {
                shopifySyncStatus = .failed(error.localizedDescription)
            }
        }
    }

    func dismissShopifySyncSummary() {
        if case .synced = shopifySyncStatus {
            shopifySyncStatus = .idle
        }
    }

    /// Adds stores the list doesn't have yet, matched by myshopify domain.
    ///
    /// Stores already in the list keep their name, color, visibility, order and pin, and
    /// nothing is ever removed, so stores added by hand are safe. New stores arrive hidden
    /// (a big organization would otherwise flood the panel) unless the list was empty.
    ///
    /// A store typed in by hand can carry a different myshopify domain than the permanent
    /// one the CLI reports (a renamed store keeps its original `abc123-xy.myshopify.com`).
    /// So a store whose domain matches nothing falls back to matching by exact name, but
    /// only when exactly one unmatched store in the list has that name.
    @discardableResult
    func mergeShopifyStores(_ remote: [ShopifyCLI.RemoteStore]) -> ShopifySyncSummary {
        let startedEmpty = stores.isEmpty
        var known = Set(stores.map { $0.myshopifyDomain.lowercased() })
        let remoteDomains = Set(remote.map { Store.normalizedDomain($0.store).lowercased() })
        var unmatchedByName: [String: [Store.ID]] = [:]
        for store in stores where !remoteDomains.contains(store.myshopifyDomain.lowercased()) {
            unmatchedByName[nameKey(store.displayName), default: []].append(store.id)
        }
        var added: [Store] = []
        var matched = 0

        let alphabetical = remote.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
        for item in alphabetical {
            let domain = Store.normalizedDomain(item.store).lowercased()
            guard domain != Store.domainSuffix else { continue }
            guard known.insert(domain).inserted else {
                matched += 1
                continue
            }
            let key = nameKey(displayName(for: item))
            if unmatchedByName[key]?.count == 1 {
                unmatchedByName[key] = nil
                matched += 1
                continue
            }
            added.append(appendStore(
                domain: domain,
                displayName: displayName(for: item),
                colorHex: Store.defaultColorHex(forIndex: stores.count),
                isVisible: startedEmpty
            ))
        }

        if !added.isEmpty {
            saveStores()
            fetchFavicons(for: added)
        }
        return ShopifySyncSummary(addedIDs: added.map(\.id), matchedCount: matched)
    }

    private func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func displayName(for store: ShopifyCLI.RemoteStore) -> String {
        let name = store.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? Store.handle(fromDomain: store.store) : name
    }
}
