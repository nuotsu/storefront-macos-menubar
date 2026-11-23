import Foundation

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
