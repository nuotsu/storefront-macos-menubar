import Observation
import SwiftUI
import ServiceManagement

/// Which part of the panel keyboard navigation currently targets — the store rail
/// (search + list) or the right-hand section-card grid.
enum PanelFocusArea: Equatable {
    case rail
    case cards
}

/// Identifies a `SettingsRootView` sidebar pane — lets the status-item menu's quick
/// links jump straight to a specific pane instead of always landing on the default.
enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case general
    case appearance
    case stores
    case sections
    case keybindings
    case howToUse
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .stores: "Stores"
        case .sections: "Sections"
        case .keybindings: "Keybindings"
        case .howToUse: "How to use"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .stores: "bag"
        case .sections: "square.grid.2x2"
        case .keybindings: "keyboard"
        case .howToUse: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

/// `@Observable` rather than `ObservableObject`: this one object backs both the panel
/// and the whole Settings tree, and holds per-keystroke state (`query`, `searchQueries`).
/// With `objectWillChange` semantics a single character typed into the rail invalidated
/// every view that held it — the rail, all 11 section cards and ~30 link rows. Observation
/// tracks reads per property, so only the views that actually read what changed re-run.
@Observable
@MainActor
final class AppState {
    var stores: [Store]
    var selectedStoreID: Store.ID?
    var query: String = ""
    var settings: AppSettings
    var focusArea: PanelFocusArea = .rail
    var focusedSectionIndex: Int = 0
    var focusedRowIndex: Int = 0
    /// Bumped only by keyboard card navigation so the detail column scrolls for arrows,
    /// not when hover/click updates the focused section.
    private(set) var cardScrollGeneration: UInt = 0
    /// After a keyboard-driven scroll, card-link hover activation stays off until the
    /// pointer actually moves — so a stationary mouse that lands on a link mid-scroll
    /// does not steal the active row.
    private(set) var cardLinkHoverArmed = true
    var selectedSettingsTab: SettingsTab = .general
    /// Sparkle found an OTA update — panel rail shows an Update button while true.
    var updateAvailable = false
    /// Display version of the pending Sparkle update (e.g. `"0.4.2"`), when known.
    var pendingUpdateVersion: String? = nil
    /// Bumped when the *stored* appearance preference changes so Settings can remount and
    /// pick up fresh dynamic colors (Dark → System was leaving cards/sidebar stuck dark).
    private(set) var appearanceRevision: UInt = 0
    /// Bumped when the *system* appearance flips. Distinct from `appearanceRevision`,
    /// which drives a `.id()` remount of the whole Settings window — far too heavy to do
    /// on every OS theme change. Nothing stored changes on a system flip, but
    /// `AppearancePreference.colorScheme` resolves `.system` against
    /// `NSApp.effectiveAppearance` at call time, so views that apply
    /// `.preferredColorScheme` need an explicit signal to re-evaluate.
    private(set) var systemAppearanceRevision: UInt = 0
    /// Row IDs whose inline search field is currently expanded, per store — shared here
    /// (rather than local view state) so a keyboard shortcut can toggle a row's search
    /// regardless of which `CardLinkRow` instance it belongs to, and keyed per store so
    /// switching stores doesn't show/hide an unrelated store's search boxes.
    var expandedSearchRowIDs: [Store.ID: Set<String>] = [:]
    /// Typed-but-not-yet-cleared search text per store/row, so switching stores and back
    /// (which tears down and recreates `CardLinkRow`, discarding any local `@State`)
    /// doesn't lose what the user typed.
    var searchQueries: [Store.ID: [String: String]] = [:]
    /// Paired with `linkSearchSelectAllGeneration` — the row whose search field should
    /// select-all after a ⌃S focus so leftover query text is replace-ready.
    var linkSearchSelectAllRowID: String?
    var linkSearchSelectAllGeneration: UInt = 0

    @ObservationIgnored private let persistence: PersistenceStore
    /// In-flight debounced store write — see `scheduleSaveStores()`.
    @ObservationIgnored private var pendingStoreSave: Task<Void, Never>?
    /// Cached `visibleStores` result — fingerprint includes visibility / favorite / sort.
    @ObservationIgnored private var visibleStoresCache: (fingerprint: Int, stores: [Store])?

    init(persistence: PersistenceStore = .shared) {
        self.persistence = persistence
        let loaded = persistence.loadStores()
        self.stores = loaded
        self.selectedStoreID = loaded.first(where: { $0.isVisible })?.id ?? loaded.first?.id
        self.settings = persistence.loadSettings()
        reconcileLaunchAtLogin()
        AppearancePreference.apply(settings.appearancePreference)
    }

    /// `SMAppService`'s registration can drift from our stored setting (e.g. the user
    /// removes the login item directly via System Settings) — correct our copy to match
    /// reality on launch rather than trusting a possibly-stale stored value.
    private func reconcileLaunchAtLogin() {
        let actuallyEnabled = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin != actuallyEnabled {
            settings.launchAtLogin = actuallyEnabled
        }
    }

    /// Registers/unregisters the app as a login item to match the toggle. Reverts to
    /// whatever `SMAppService` actually reports if the call fails, so the UI never
    /// claims a state that isn't real.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
        } catch {
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        saveSettings()
    }

    func setAppearancePreference(_ preference: AppearancePreference) {
        settings.appearancePreference = preference
        AppearancePreference.apply(preference)
        appearanceRevision &+= 1
        saveSettings()
    }

    /// Call when macOS itself flips Light↔Dark. See `systemAppearanceRevision`.
    func noteSystemAppearanceChanged() {
        systemAppearanceRevision &+= 1
    }

    func setAppIconPreference(_ preference: AppIconPreference) {
        settings.appIconPreference = preference
        AppIconPreference.apply(preference)
        saveSettings()
    }

    func setMenuBarIconPreference(_ preference: MenuBarIconPreference) {
        settings.menuBarIconPreference = preference
        AppDelegate.shared?.applyMenuBarIcon()
        saveSettings()
    }

    func setOpaqueMenuBarWidget(_ opaque: Bool) {
        settings.opaqueMenuBarWidget = opaque
        AppDelegate.shared?.applyPanelBackgroundOpacity(opaque)
        saveSettings()
    }

    func setWidgetThemePreference(_ preference: WidgetThemePreference) {
        settings.widgetThemePreference = preference
        // Re-apply so the panel picks up Shopify-forced light / opaque hosting fill.
        AppearancePreference.apply(settings.appearancePreference)
        AppDelegate.shared?.applyPanelBackgroundOpacity(settings.opaqueMenuBarWidget)
        saveSettings()
    }

    func setOpenUnderMouse(_ enabled: Bool) {
        settings.openUnderMouse = enabled
        saveSettings()
    }

    func setShowStarredStoresInMenuBar(_ enabled: Bool) {
        settings.showStarredStoresInMenuBar = enabled
        saveSettings()
        AppDelegate.shared?.syncMenuBarFavorites()
    }

    /// Favorited stores first (starring moves a store to the top), each group
    /// otherwise in the user's chosen order.
    var visibleStores: [Store] {
        let fingerprint = Self.visibleStoresFingerprint(stores)
        if let cache = visibleStoresCache, cache.fingerprint == fingerprint {
            return cache.stores
        }
        let value = stores.filter(\.isVisible).sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.sortOrder < rhs.sortOrder
        }
        visibleStoresCache = (fingerprint, value)
        return value
    }

    private static func visibleStoresFingerprint(_ stores: [Store]) -> Int {
        var hasher = Hasher()
        for store in stores {
            hasher.combine(store.id)
            hasher.combine(store.isVisible)
            hasher.combine(store.isFavorite)
            hasher.combine(store.sortOrder)
        }
        return hasher.finalize()
    }

    /// Visible starred stores in rail order — drives the adjacent menu bar favicons.
    var menuBarFavoriteStores: [Store] {
        stores
            .filter { $0.isVisible && $0.isFavorite }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var selectedStore: Store? {
        stores.first { $0.id == selectedStoreID }
    }

    /// `visibleStores`, further narrowed by the rail's search query — the exact list
    /// the rail renders, shared here so keyboard navigation and `⌘1`-`⌘9` index into
    /// the same set of rows the user actually sees.
    var filteredStores: [Store] {
        let stores = visibleStores
        guard !query.isEmpty else { return stores }
        return stores.filter { $0.matchesSearchQuery(query) }
    }

    /// All enabled sections, in display order — the exact list `StoreDetailView` renders,
    /// shared here so keyboard navigation can resolve a focused card/row without needing
    /// its own view-layer state.
    var enabledSections: [SectionID] {
        settings.sectionOrder.filter { settings.enabledSections.contains($0) }
    }

    func select(_ store: Store) {
        selectedStoreID = store.id
    }

    // MARK: - Keyboard navigation

    func selectAdjacentStore(offset: Int) {
        let stores = filteredStores
        guard !stores.isEmpty else { return }
        let currentIndex = stores.firstIndex(where: { $0.id == selectedStoreID }) ?? 0
        let count = stores.count
        let newIndex = ((currentIndex + offset) % count + count) % count
        select(stores[newIndex])
    }

    /// `⌘1`-`⌘9` jump straight to the Nth visible store, from either the rail or the
    /// card grid — 1-based to match the digit the user actually presses.
    func selectStore(atShortcutIndex index: Int) {
        let stores = filteredStores
        guard index >= 1, index <= stores.count else { return }
        select(stores[index - 1])
        // Focus the first card/link so ←/→ work immediately after a ⌘N jump.
        enterCards()
    }

    func enterCards() {
        let sections = enabledSections
        guard !sections.isEmpty else { return }
        focusArea = .cards
        focusedSectionIndex = 0
        focusedRowIndex = 0
        requestCardScroll()
    }

    func exitToRail() {
        focusArea = .rail
    }

    /// Makes a specific card link the sole active target (hover/click). Keyboard arrows
    /// use the same indices — hover overrides whatever arrows last selected.
    /// - Parameter fromHover: when true, ignored while hover is disarmed after a scroll.
    func focusCardLink(section: SectionID, rowIndex: Int, fromHover: Bool = false) {
        if fromHover && !cardLinkHoverArmed { return }
        let sections = enabledSections
        guard let sectionIndex = sections.firstIndex(of: section) else { return }
        let rows = StaticLinkCatalog.rows(for: section)
        guard rowIndex >= 0, rowIndex < rows.count else { return }
        focusArea = .cards
        focusedSectionIndex = sectionIndex
        focusedRowIndex = rowIndex
    }

    /// Left/Right — moves between cards in the same flat reading order the grid already
    /// lays out in (a flat index into `enabledSections` reads left-to-right, row-to-row,
    /// so no 2D math is needed). Wraps at either end — Esc is the way back to the rail.
    func moveCardFocus(offset: Int) {
        let sections = enabledSections
        let sectionCount = sections.count
        guard sectionCount > 0 else { return }
        focusedSectionIndex = ((focusedSectionIndex + offset) % sectionCount + sectionCount) % sectionCount
        focusedRowIndex = 0
        requestCardScroll()
    }

    /// Up/Down while focused on a card — wraps within that card's own rows, does not
    /// spill into the next/previous card.
    func moveRowFocus(offset: Int) {
        let sections = enabledSections
        guard focusedSectionIndex < sections.count else { return }
        let rowCount = StaticLinkCatalog.rows(for: sections[focusedSectionIndex]).count
        guard rowCount > 0 else { return }
        focusedRowIndex = ((focusedRowIndex + offset) % rowCount + rowCount) % rowCount
    }

    /// Keyboard card navigation only — arms a one-shot scroll and ignores hover
    /// activation until the next real mouse move.
    private func requestCardScroll() {
        cardLinkHoverArmed = false
        cardScrollGeneration &+= 1
    }

    /// Called from the panel mouse-tracking overlay on real pointer movement.
    func notePanelMouseMoved() {
        guard !cardLinkHoverArmed else { return }
        cardLinkHoverArmed = true
    }

    /// The `LinkRow` the keyboard is currently focused on within the card grid, shared by
    /// `openFocusedLink()`/`openFocusedCreateLink()`/`toggleSearchForFocusedLink()` so they
    /// don't each repeat the same section/row lookup.
    private var focusedRow: LinkRow? {
        let sections = enabledSections
        guard focusArea == .cards, focusedSectionIndex < sections.count else { return nil }
        let rows = StaticLinkCatalog.rows(for: sections[focusedSectionIndex])
        guard focusedRowIndex < rows.count else { return nil }
        return rows[focusedRowIndex]
    }

    /// Return — opens the currently keyboard-focused link, same as clicking it.
    func openFocusedLink() {
        guard let store = selectedStore, let row = focusedRow,
              let url = row.url(for: store.myshopifyDomain) else { return }
        openStoreLink(url, keepOpen: false)
    }

    /// Opens the focused row's "New +" create link, if it has one.
    func openFocusedCreateLink() {
        guard let store = selectedStore, let row = focusedRow,
              let url = row.createURL(for: store.myshopifyDomain) else { return }
        openStoreLink(url, keepOpen: false)
    }

    /// Opens the selected store's admin (panel shortcut; closes the panel).
    func openSelectedAdmin() {
        guard let url = selectedStore?.adminURL else { return }
        openStoreLink(url, keepOpen: false)
    }

    /// Opens the selected store's online storefront (panel shortcut; closes the panel).
    func openSelectedOnlineStore() {
        guard let url = selectedStore?.shopURL else { return }
        openStoreLink(url, keepOpen: false)
    }

    /// Opens Shopify Help Center (panel shortcut; closes the panel).
    func openSelectedSupport() {
        guard let url = selectedStore?.supportURL else { return }
        openStoreLink(url, keepOpen: false)
    }

    /// Focused card row id when that row supports inline search; else `nil`.
    func focusedSearchableRowID() -> String? {
        guard let row = focusedRow, row.supportsSearch else { return nil }
        return row.id
    }

    /// Whether the focused searchable row's search field is currently expanded.
    func isFocusedLinkSearchExpanded() -> Bool {
        guard let store = selectedStore, let rowID = focusedSearchableRowID() else { return false }
        return expandedSearchRowIDs[store.id]?.contains(rowID) ?? false
    }

    /// Ask the matching row search field to select its contents (after focus settles).
    func requestLinkSearchSelectAll(rowID: String) {
        linkSearchSelectAllRowID = rowID
        linkSearchSelectAllGeneration &+= 1
    }

    /// Toggles the focused row's inline search field, if it supports search. Returns
    /// the row's id and its new expanded state so the caller (which owns the `@FocusState`
    /// needed to actually focus the field) can react — `nil` if the focused row can't search.
    /// Expand/collapse only — focus-first when already open is handled by the panel.
    @discardableResult
    func toggleSearchForFocusedLink() -> (rowID: String, isNowExpanded: Bool)? {
        guard let store = selectedStore, let row = focusedRow, row.supportsSearch else { return nil }
        if expandedSearchRowIDs[store.id, default: []].contains(row.id) {
            expandedSearchRowIDs[store.id]?.remove(row.id)
            return (row.id, false)
        } else {
            expandedSearchRowIDs[store.id, default: []].insert(row.id)
            return (row.id, true)
        }
    }

    /// Writes both files. Prefer `saveStores()` / `saveSettings()` where only one
    /// domain changed — each `save()` re-encodes and atomically rewrites *both*.
    func save() {
        saveStores()
        saveSettings()
    }

    func saveStores() {
        pendingStoreSave?.cancel()
        pendingStoreSave = nil
        persistence.save(stores: stores)
        AppDelegate.shared?.syncMenuBarFavorites()
    }

    func saveSettings() {
        persistence.save(settings: settings)
    }

    /// Coalesces bursts of store writes. `NSColorPanel` emits continuous updates while
    /// the user drags the color wheel, and each one was re-encoding and atomically
    /// rewriting stores.json. Anything that can fire at drag rate should use this;
    /// discrete actions stay on the immediate path.
    func scheduleSaveStores() {
        pendingStoreSave?.cancel()
        pendingStoreSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.pendingStoreSave = nil
            self.persistence.save(stores: self.stores)
            AppDelegate.shared?.syncMenuBarFavorites()
        }
    }

    /// Writes anything still in flight. Must be called before the app can go away, or a
    /// debounced change made in the last 300 ms is lost.
    func flushPendingSaves() {
        guard pendingStoreSave != nil else { return }
        pendingStoreSave?.cancel()
        pendingStoreSave = nil
        persistence.save(stores: stores)
        AppDelegate.shared?.syncMenuBarFavorites()
    }

    func addStore(domain: String, displayName: String, colorHex: String) {
        let accountID = stores.first?.accountID ?? UUID()
        let nextOrder = (stores.map(\.sortOrder).max() ?? -1) + 1
        let store = Store(accountID: accountID, myshopifyDomain: domain, displayName: displayName, colorHex: colorHex, sortOrder: nextOrder)
        stores.append(store)
        if selectedStoreID == nil { selectedStoreID = store.id }
        saveStores()
        fetchFavicon(for: store)
    }

    /// Updates identity fields for an existing store. Refetches the favicon when the domain changes.
    func updateStore(_ store: Store, displayName: String, domain: String) {
        guard let index = stores.firstIndex(where: { $0.id == store.id }) else { return }
        let domainChanged = stores[index].myshopifyDomain != domain
        stores[index].displayName = displayName
        stores[index].myshopifyDomain = domain
        saveStores()
        if domainChanged {
            FaviconStore.shared.remove(storeID: store.id)
            fetchFavicon(for: stores[index], force: true)
        }
    }

    /// Force-refreshes favicons for every store (Settings → Stores). Returns how many icons were saved.
    @discardableResult
    func refreshFavicons() async -> Int {
        await FaviconStore.shared.fetch(stores: stores, force: true)
    }

    private func fetchFavicon(for store: Store, force: Bool = false) {
        Task {
            await FaviconStore.shared.fetch(stores: [store], force: force)
        }
    }

    // MARK: - CSV import/export

    /// "Display Name,Domain,Color" — one row per store, in panel order.
    func storesCSV() -> String {
        var lines = ["Display Name,Domain,Color"]
        for store in stores.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            lines.append("\(CSV.escape(store.displayName)),\(CSV.escape(store.myshopifyDomain)),\(store.colorHex)")
        }
        return lines.joined(separator: "\n")
    }

    /// Adds a store per data row (skipping the header row and any duplicate domains).
    /// Returns the number of stores actually added.
    @discardableResult
    func importStoresCSV(_ contents: String) -> Int {
        let palette = ["1f6f4a", "c07a2c", "3a6ea8", "7a4b8c", "4a7a5c", "a8563a", "5c9fd6", "a37bb8"]
        var added = 0
        let rows = CSV.parse(contents)
        for row in rows.dropFirst() where row.count >= 2 {
            let displayName = row[0].trimmingCharacters(in: .whitespaces)
            let rawDomain = row[1].trimmingCharacters(in: .whitespaces)
            guard !displayName.isEmpty, !rawDomain.isEmpty else { continue }
            let domain = Store.normalizedDomain(rawDomain)
            guard !stores.contains(where: { $0.myshopifyDomain == domain }) else { continue }
            let colorHex = row.count >= 3 && !row[2].isEmpty ? row[2] : palette[stores.count % palette.count]
            addStore(domain: domain, displayName: displayName, colorHex: colorHex)
            added += 1
        }
        return added
    }

    /// "Preset,Section,Title,Enabled" — one row per section per saved preset (built-ins omitted).
    func sectionPresetsCSV() -> String {
        var lines = ["Preset,Section,Title,Enabled"]
        for preset in settings.savedSectionPresets {
            for section in preset.sectionOrder {
                let enabled = preset.enabledSections.contains(section) ? "true" : "false"
                lines.append(
                    "\(CSV.escape(preset.name)),\(section.rawValue),\(CSV.escape(section.title)),\(enabled)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Merges saved presets from a CSV by name (case-insensitive). Same name overwrites that
    /// preset's layout (keeps `id`); new names are appended. Does not delete missing names or
    /// change the currently applied section layout. Returns how many presets were upserted.
    @discardableResult
    func importSectionPresetsCSV(_ contents: String) -> Int {
        let rows = CSV.parse(contents)
        guard !rows.isEmpty else { return 0 }

        var dataRows = rows
        var presetIndex = 0
        var sectionIndex = 1
        var enabledIndex = 3

        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if header.contains("preset") || header.first == "name" {
            dataRows = Array(rows.dropFirst())
            if let i = header.firstIndex(of: "preset") ?? header.firstIndex(of: "name") {
                presetIndex = i
            }
            if let i = header.firstIndex(of: "section") ?? header.firstIndex(of: "id") {
                sectionIndex = i
            }
            if let i = header.firstIndex(of: "enabled") {
                enabledIndex = i
            } else if header.count >= 4 {
                enabledIndex = 3
            } else if header.count >= 3 {
                enabledIndex = 2
            }
        }

        var grouped: [(name: String, rows: [[String]])] = []
        var indexByLoweredName: [String: Int] = [:]

        for row in dataRows where row.count > max(presetIndex, sectionIndex) {
            let name = row[presetIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if let existing = indexByLoweredName[key] {
                grouped[existing].rows.append(row)
            } else {
                indexByLoweredName[key] = grouped.count
                grouped.append((name: name, rows: [row]))
            }
        }

        var upserted = 0
        for group in grouped {
            let layoutRows = group.rows.map { row -> [String] in
                let section = row.indices.contains(sectionIndex) ? row[sectionIndex] : ""
                let enabled = row.indices.contains(enabledIndex) ? row[enabledIndex] : "true"
                return [section, "", enabled]
            }
            guard let layout = Self.parseSectionLayoutRows(layoutRows) else { continue }
            let lowered = group.name.lowercased()
            if let index = settings.savedSectionPresets.firstIndex(where: { $0.name.lowercased() == lowered }) {
                settings.savedSectionPresets[index].sectionOrder = layout.order
                settings.savedSectionPresets[index].enabledSections = layout.enabled
            } else {
                settings.savedSectionPresets.append(
                    SavedSectionPreset(
                        name: group.name,
                        sectionOrder: layout.order,
                        enabledSections: layout.enabled
                    )
                )
            }
            upserted += 1
        }

        guard upserted > 0 else { return 0 }
        saveSettings()
        return upserted
    }

    /// Parses section layout rows shaped like `[sectionKey, title?, enabledFlag]`.
    private static func parseSectionLayoutRows(
        _ dataRows: [[String]]
    ) -> (order: [SectionID], enabled: Set<SectionID>, applied: Int)? {
        var order: [SectionID] = []
        var enabled = Set<SectionID>()
        var seen = Set<SectionID>()
        var applied = 0

        for row in dataRows where !row.isEmpty {
            let key = row[0].trimmingCharacters(in: .whitespaces)
            guard let section = resolveSectionID(key) else { continue }
            guard seen.insert(section).inserted else { continue }
            order.append(section)
            let flag = row.count >= 3
                ? row[2]
                : (row.count >= 2 ? row[1] : "true")
            if isTruthyCSVFlag(flag) {
                enabled.insert(section)
            }
            applied += 1
        }

        for section in SectionID.defaultOrder where !seen.contains(section) {
            order.append(section)
            enabled.insert(section)
        }

        guard applied > 0 else { return nil }
        return (order, enabled, applied)
    }

    private static func resolveSectionID(_ key: String) -> SectionID? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if let byRaw = SectionID(rawValue: trimmed) { return byRaw }
        let lowered = trimmed.lowercased()
        if let byRaw = SectionID(rawValue: lowered) { return byRaw }
        return SectionID.allCases.first { $0.title.lowercased() == lowered }
    }

    private static func isTruthyCSVFlag(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1", "enabled", "on": return true
        default: return false
        }
    }

    func toggleFavorite(_ store: Store) {
        guard let index = stores.firstIndex(where: { $0.id == store.id }) else { return }
        stores[index].isFavorite.toggle()
        saveStores()
    }

    func removeStore(_ store: Store) {
        stores.removeAll { $0.id == store.id }
        FaviconStore.shared.remove(storeID: store.id)
        saveStores()
    }

    func removeAllStores() {
        stores.removeAll()
        FaviconStore.shared.removeAll()
        selectedStoreID = nil
        saveStores()
    }
}
