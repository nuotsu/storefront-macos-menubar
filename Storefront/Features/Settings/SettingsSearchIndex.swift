import Foundation

/// One searchable settings destination — selecting a hit navigates to `tab`.
struct SettingsSearchHit: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tab: SettingsTab
    let keywords: [String]
    /// Title, subtitle and keywords pre-lowered at construction. The static index is a
    /// `static let`, so these are built once per process instead of re-lowering every
    /// field of all ~68 entries on each keystroke. Kept as separate strings rather than
    /// one joined string so a query can't match across a field boundary.
    let haystack: [String]

    /// `query` must already be trimmed and lowercased — see `SettingsSearchIndex.hits`.
    func matches(loweredQuery query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return haystack.contains { $0.contains(query) }
    }
}

enum SettingsSearchIndex {
    /// Static labels / controls across Settings panes.
    static let staticHits: [SettingsSearchHit] = [
        // Panes themselves
        hit("pane.stores", "Stores", "Stores", .stores, ["shopify", "myshopify", "store list"]),
        hit("pane.sections", "Sections", "Sections", .sections, ["admin sections", "cards", "panel"]),
        hit("pane.keybindings", "Keybindings", "Keybindings", .keybindings, ["hotkey", "keyboard", "keymap", "shortcuts"]),
        hit("pane.howToUse", "How to use", "How to use", .howToUse, ["guide", "help", "onboarding", "getting started", "tutorial"]),
        hit("pane.general", "General", "General", .general, ["preferences", "options"]),
        hit("pane.appearance", "Appearance", "Appearance", .appearance, ["theme", "icon", "look", "visual"]),
        hit("pane.about", "About", "About", .about, ["version", "credits", "update"]),

        // Stores
        hit("stores.add", "Add Store", "Stores", .stores, ["new store", "create", "add store", "+"]),
        hit("stores.importExport", "Import & Export", "Stores", .stores, ["csv", "import", "export", "backup"]),
        hit("stores.import", "Import CSV", "Stores", .stores, ["csv", "import"]),
        hit("stores.export", "Export CSV", "Stores", .stores, ["csv", "export"]),
        hit("stores.deleteAll", "Delete All", "Stores", .stores, ["remove", "clear"]),
        hit("stores.hideAll", "Hide All / Show All", "Stores", .stores, ["visibility", "enable"]),
        hit("stores.refreshFavicons", "Refresh favicons", "Stores", .stores, ["favicon", "icon", "logo"]),
        hit("stores.displayName", "Display name", "Stores", .stores, ["name", "rename"]),
        hit("stores.accent", "Accent color", "Stores", .stores, ["color", "swatch"]),
        hit("stores.domain", "Store domain", "Stores", .stores, ["myshopify.com", "url"]),

        // Sections
        hit("sections.presets", "Preset", "Sections", .sections, ["layout", "preset", "role", "presets", "save preset"]),
        hit("sections.preset.default", "Default", "Sections", .sections, ["preset", "default order"]),
        hit("sections.preset.storeManager", "Store manager", "Sections", .sections, ["preset", "orders", "customers"]),
        hit("sections.preset.marketer", "Marketer", "Sections", .sections, ["preset", "analytics", "discounts"]),
        hit("sections.preset.developer", "Developer", "Sections", .sections, ["preset", "themes", "content"]),
        hit("sections.preset.custom", "Create new", "Sections", .sections, ["preset", "custom", "save layout"]),
        hit("sections.preset.save", "Save current", "Sections", .sections, ["save", "named preset", "custom preset", "save preset"]),
        hit("sections.preset.rename", "Rename Preset", "Sections", .sections, ["rename", "saved preset"]),
        hit("sections.preset.delete", "Delete Preset", "Sections", .sections, ["remove", "saved preset"]),
        hit("sections.library", "Library", "Sections", .sections, ["csv", "preset library", "import", "export", "transfer"]),
        hit("sections.importPresets", "Import", "Sections", .sections, ["csv", "preset library", "import presets"]),
        hit("sections.exportPresets", "Export", "Sections", .sections, ["csv", "preset library", "export presets"]),
        hit("sections.enableAll", "Enable All / Disable All", "Sections", .sections, ["toggle"]),
        hit("sections.reorder", "Reorder sections", "Sections", .sections, ["drag", "order"]),

        // Keybindings
        hit("keybindings.global", "Open or close the panel", "Keybindings", .keybindings, ["global hotkey", "toggle panel"]),
        hit("keybindings.quit", "Quit Storefront", "Keybindings", .keybindings, ["quit", "exit"]),
        hit("keybindings.focusSearch", "Focus the store search field", "Keybindings", .keybindings, ["search", "find store"]),
        hit("keybindings.storeList", "Move through the store list", "Keybindings", .keybindings, ["arrows", "navigate"]),
        hit("keybindings.jumpStore", "Jump to a specific store", "Keybindings", .keybindings, ["command", "⌘1", "⌘9"]),
        hit("keybindings.openAdmin", "Open Admin", "Keybindings", .keybindings, ["admin", "backend"]),
        hit("keybindings.openOnlineStore", "Open Online Store", "Keybindings", .keybindings, ["storefront", "online store"]),
        hit("keybindings.openSupport", "Open Support", "Keybindings", .keybindings, ["help", "help center"]),
        hit("keybindings.sectionGrid", "Move between cards", "Keybindings", .keybindings, ["sections", "grid"]),
        hit("keybindings.openLink", "Open the focused link", "Keybindings", .keybindings, ["return", "enter"]),
        hit("keybindings.keepOpen", "Open a link and keep the panel open", "Keybindings", .keybindings, ["command-click", "⌘-click"]),
        hit("keybindings.linkSearch", "Toggle search on the focused link", "Keybindings", .keybindings, ["inline search"]),
        hit("keybindings.create", "Create new on the focused link", "Keybindings", .keybindings, ["create", "add", "new"]),
        hit("keybindings.escape", "Step back, then close the panel", "Keybindings", .keybindings, ["escape", "esc"]),

        // General
        hit("general.login", "Launch at login", "General", .general, ["startup", "login item"]),
        hit("general.menubar", "Show in menu bar", "General", .general, ["status item", "menu bar"]),
        hit("general.starredMenuBar", "Favorited stores in menu bar", "General", .general, ["favorite", "star", "favicon", "status item", "menu bar"]),
        hit("general.openUnderMouse", "Open under mouse", "General", .general, ["pointer", "cursor", "floating", "popover", "menu bar icon"]),
        hit("general.dock", "Show in Dock", "General", .general, ["dock icon", "activation"]),

        // Appearance
        hit("appearance.theme", "Theme", "Appearance", .appearance, ["macos", "shopify", "polaris", "admin"]),
        hit("appearance.appearance", "Appearance", "Appearance", .appearance, ["theme", "light", "dark", "system", "auto"]),
        hit("appearance.opaqueBackground", "Widget background", "Appearance", .appearance, ["opaque", "transparent", "glass", "vibrancy", "liquid glass", "widget"]),
        hit("appearance.appIcon", "App Icon", "Appearance", .appearance, ["icon", "dock", "light", "dark", "auto", "system"]),
        hit("appearance.menuBarIcon", "Menu bar icon", "Appearance", .appearance, ["cart", "store", "shopify", "status item", "menu bar", "outline", "filled"]),

        // How to use
        hit("howto.addStores", "Add your stores", "How to use", .howToUse, ["add store", "myshopify", "import csv"]),
        hit("howto.customizeCards", "Customize your cards", "How to use", .howToUse, ["sections", "presets", "reorder"]),
        hit("howto.navigate", "Navigate the panel", "How to use", .howToUse, ["keyboard", "arrows", "hotkey", "menu bar"]),

        // About
        hit("about.version", "Version", "About", .about, ["build", "release"]),
        hit("about.repo", "Repository", "About", .about, ["github", "source", "changelog", "releases"]),
        hit("about.website", "Website", "About", .about, ["homepage", "site", "docs", "documentation", "help", "guide"]),
        hit("about.changelog", "Changelog", "About", .about, ["releases", "github", "what's new", "release notes"]),
        hit("about.dev", "Developed by", "About", .about, ["nuotsu", "author"]),
        hit("about.updates", "Check for Updates", "About", .about, ["sparkle", "update"]),
        hit("about.feedback", "Send Feedback", "About", .about, ["contact", "support", "feedback"]),
    ]

    static func hits(query: String, storeNames: [String], sectionTitles: [String]) -> [SettingsSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Bail before building anything — an empty query shows no hits at all.
        guard !q.isEmpty else { return [] }

        var matched = staticHits.filter { $0.matches(loweredQuery: q) }

        for name in storeNames where !name.isEmpty {
            let storeHit = hit("store.\(name)", name, "Stores", .stores, ["store", "shop"])
            if storeHit.matches(loweredQuery: q) { matched.append(storeHit) }
        }
        for title in sectionTitles {
            let sectionHit = hit("section.\(title)", title, "Sections", .sections, ["section", "admin", "card"])
            if sectionHit.matches(loweredQuery: q) { matched.append(sectionHit) }
        }

        return matched
    }

    private static func hit(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ tab: SettingsTab,
        _ keywords: [String]
    ) -> SettingsSearchHit {
        SettingsSearchHit(
            id: id,
            title: title,
            subtitle: subtitle,
            tab: tab,
            keywords: keywords,
            haystack: ([title, subtitle] + keywords).map { $0.lowercased() }
        )
    }
}
