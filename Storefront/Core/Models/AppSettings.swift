import AppKit
import SwiftUI

/// User-saved section layout (order + enabled set) for Settings → Sections presets.
struct SavedSectionPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var sectionOrder: [SectionID]
    var enabledSections: Set<SectionID>
}

/// Dock / About icon choice — mirrors cmux `AppIconMode`.
///
/// Auto (and Light/Dark when they already match system) clear
/// `applicationIconImage` so the Dock uses Icon Composer `AppIcon` with the
/// same Liquid Glass chrome/size. Forced Light-on-dark / Dark-on-light uses an
/// inset imageset so the tile scale matches that chrome.
enum AppIconPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Settings order: Auto → Light → Dark.
    static let displayOrder: [AppIconPreference] = [.system, .light, .dark]

    /// Thumbnail asset. Auto uses Light for a single-tile fallback.
    var imageName: String {
        switch self {
        case .system, .light: "AppIconLight"
        case .dark: "AppIconDark"
        }
    }

    /// Updates the running app's Dock / About icon.
    @MainActor
    static func apply(_ preference: AppIconPreference) {
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch preference {
        case .system:
            NSApp.applicationIconImage = nil
        case .light:
            // Same chrome/size as Auto whenever system is already Light.
            NSApp.applicationIconImage = systemDark ? dockOverrideImage(named: "AppIconLight") : nil
        case .dark:
            // Same chrome/size as Auto whenever system is already Dark.
            NSApp.applicationIconImage = systemDark ? nil : dockOverrideImage(named: "AppIconDark")
        }
    }

    /// Pads a flattened imageset so `applicationIconImage` matches the Dock’s
    /// system App Icon content scale (full-bleed overrides read ~15–20% larger).
    @MainActor
    private static func dockOverrideImage(named name: String) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
        let canvas: CGFloat = 1024
        // Empirically matches Icon Composer + Dock Liquid Glass tile scale.
        let content: CGFloat = canvas * 0.80
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(
            x: (canvas - content) / 2,
            y: (canvas - content) / 2,
            width: content,
            height: content
        )
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [
            .interpolation: NSImageInterpolation.high
        ])
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

/// Menu bar status-item glyph — SF Symbol bag, Polaris Cart / Store × outline / filled,
/// or the single-form Shopify glyph.
enum MenuBarIconPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case bag
    case bagFilled
    case cart
    case cartFilled
    case store
    case storeFilled
    case shopify

    var id: Self { self }

    enum Family: String, CaseIterable, Identifiable {
        case bag
        case cart
        case store
        case shopify

        var id: Self { self }

        var title: String {
            switch self {
            case .bag: "Bag"
            case .cart: "Cart"
            case .store: "Store"
            case .shopify: "Shopify"
            }
        }

        /// Settings chip order: Bag → Store → Cart → Shopify.
        static let displayOrder: [Family] = [.bag, .store, .cart, .shopify]
    }

    var family: Family {
        switch self {
        case .bag, .bagFilled: .bag
        case .cart, .cartFilled: .cart
        case .store, .storeFilled: .store
        case .shopify: .shopify
        }
    }

    /// Shopify has only one form — never "filled".
    var isFilled: Bool {
        switch self {
        case .bagFilled, .cartFilled, .storeFilled: true
        case .bag, .cart, .store, .shopify: false
        }
    }

    var title: String { family.title }

    /// SF Symbol for bag options (nil for Polaris/Shopify asset glyphs).
    var systemSymbolName: String? {
        switch self {
        case .bag: "bag"
        case .bagFilled: "bag.fill"
        case .cart, .cartFilled, .store, .storeFilled, .shopify: nil
        }
    }

    /// Asset catalog imageset name for Polaris/Shopify glyphs (nil for SF Symbol bag).
    var assetName: String? {
        switch self {
        case .bag, .bagFilled: nil
        case .cart: "CartIcon"
        case .cartFilled: "CartFilledIcon"
        case .store: "StoreIcon"
        case .storeFilled: "StoreFilledIcon"
        case .shopify: "ShopifyIcon"
        }
    }

    static func preference(family: Family, filled: Bool) -> MenuBarIconPreference {
        switch (family, filled) {
        case (.bag, false): .bag
        case (.bag, true): .bagFilled
        case (.cart, false): .cart
        case (.cart, true): .cartFilled
        case (.store, false): .store
        case (.store, true): .storeFilled
        case (.shopify, _): .shopify
        }
    }
}

/// Visual language for the menu bar widget — native macOS chrome vs Shopify Admin / Polaris.
enum WidgetThemePreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case macOS
    case shopify

    var id: Self { self }

    var title: String {
        switch self {
        case .macOS: "macOS"
        case .shopify: "Shopify"
        }
    }

    /// Settings order: macOS → Shopify.
    static let displayOrder: [WidgetThemePreference] = [.macOS, .shopify]

    var isShopify: Bool { self == .shopify }
}

/// App-wide light/dark preference for the menu bar panel and Settings window.
enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case light
    case dark
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Auto"
        }
    }

    /// System Settings order: Auto → Light → Dark.
    static let displayOrder: [AppearancePreference] = [.system, .light, .dark]

    /// Always a concrete aqua / darkAqua. `.system` resolves against the real macOS
    /// appearance (`NSApp.appearance` must be `nil` first) — assigning `nil` to a
    /// window after `.darkAqua` can leave Liquid Glass / dynamic colors stuck dark.
    var nsAppearance: NSAppearance {
        switch self {
        case .light:
            return NSAppearance(named: .aqua) ?? NSAppearance()
        case .dark:
            return NSAppearance(named: .darkAqua) ?? NSAppearance()
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            return NSAppearance(named: match) ?? NSAppearance()
        }
    }

    /// Concrete scheme so SwiftUI sees Light↔System as a real change (not `.dark`→`nil`).
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system:
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .dark : .light
        }
    }

    /// Applies appearance to the menu bar panel and Settings window only.
    /// Never sets `NSApp.appearance` — that forces the status-item template icon to
    /// tint against the app theme instead of the menu bar (e.g. black on a dark bar).
    @MainActor
    static func apply(_ preference: AppearancePreference) {
        NSApp.appearance = nil
        AppDelegate.shared?.applyAppearancePreference(preference)
    }
}

struct AppSettings: Codable, Equatable {
    /// All sections, in display/order — separate from which are enabled, so toggling
    /// one off doesn't reshuffle the list.
    var sectionOrder: [SectionID] = SectionID.defaultOrder
    var enabledSections: Set<SectionID> = Set(SectionID.allCases)
    var launchAtLogin: Bool = false
    /// When false, the bag status item is removed from the menu bar. Toggle off/on to recreate a missing icon.
    var showInMenuBar: Bool = true
    /// When true, the app uses a regular activation policy and appears in the Dock.
    var showInDock: Bool = true
    /// When true, the widget opens as a floating panel under the pointer instead of
    /// attaching to the menu bar icon. Ignored (effectively always on) when the menu
    /// bar icon is hidden.
    var openUnderMouse: Bool = false
    /// When true, visible starred stores appear as favicons beside the menu bar glyph.
    /// No-op when the menu bar icon is hidden.
    var showStarredStoresInMenuBar: Bool = true
    /// Light / Dark / System — drives panel + Settings appearance.
    /// Ignored by the panel when `widgetThemePreference` is `.shopify` (Polaris is light).
    var appearancePreference: AppearancePreference = .system
    /// Auto / Light / Dark Dock icon (cmux-style). Auto uses Icon Composer chrome.
    var appIconPreference: AppIconPreference = .system
    /// Glyph shown in the menu bar status item (Polaris bag / cart / store).
    var menuBarIconPreference: MenuBarIconPreference = .bag
    /// When true, the menu bar widget uses opaque chrome instead of Liquid Glass vibrancy.
    /// Ignored when `widgetThemePreference` is `.shopify` (Polaris is always flat/opaque).
    var opaqueMenuBarWidget: Bool = false
    /// macOS (Liquid Glass / opaque) vs Shopify Admin Polaris chrome for the widget.
    var widgetThemePreference: WidgetThemePreference = .macOS
    var globalHotkey: KeyCombo = .default
    /// Panel-local: open the selected store's Shopify admin.
    var openAdminHotkey: KeyCombo = .openAdminDefault
    /// Panel-local: open the selected store's online storefront.
    var openOnlineStoreHotkey: KeyCombo = .openOnlineStoreDefault
    /// Panel-local: open Shopify Help Center.
    var openSupportHotkey: KeyCombo = .openSupportDefault
    /// Panel-local: focus the store search field.
    var focusSearchHotkey: KeyCombo = .focusSearchDefault
    /// Panel-local: toggle inline search on the focused link.
    var toggleLinkSearchHotkey: KeyCombo = .toggleLinkSearchDefault
    /// Panel-local: open the focused link's "New +" create URL.
    var openCreateLinkHotkey: KeyCombo = .openCreateLinkDefault
    /// Named user layouts available in the Sections presets picker (built-ins are not stored here).
    var savedSectionPresets: [SavedSectionPreset] = []
    /// When true, the Presets picker shows Custom even if the current layout still
    /// exact-matches a named/saved preset (selecting Custom is otherwise a no-op).
    var prefersCustomSectionPreset: Bool = false
    /// Sticky saved-preset selection when that preset’s layout also matches a built-in
    /// (layout matching alone would otherwise resolve to the built-in and hide Rename/Delete).
    var preferredSavedSectionPresetID: UUID? = nil

}

// Declared in an extension, not the struct body, so Swift still synthesizes the
// memberwise / no-argument init that `AppSettings()` relies on.
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sectionOrder = try c.decodeIfPresent([SectionID].self, forKey: .sectionOrder) ?? SectionID.defaultOrder
        enabledSections = try c.decodeIfPresent(Set<SectionID>.self, forKey: .enabledSections) ?? Set(SectionID.allCases)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? true
        openUnderMouse = try c.decodeIfPresent(Bool.self, forKey: .openUnderMouse) ?? false
        showStarredStoresInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showStarredStoresInMenuBar) ?? true
        appearancePreference = try c.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .system
        appIconPreference = try c.decodeIfPresent(AppIconPreference.self, forKey: .appIconPreference) ?? .system
        menuBarIconPreference = try c.decodeIfPresent(MenuBarIconPreference.self, forKey: .menuBarIconPreference) ?? .bag
        opaqueMenuBarWidget = try c.decodeIfPresent(Bool.self, forKey: .opaqueMenuBarWidget) ?? false
        widgetThemePreference = try c.decodeIfPresent(WidgetThemePreference.self, forKey: .widgetThemePreference) ?? .macOS
        globalHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .globalHotkey) ?? .default
        openAdminHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .openAdminHotkey) ?? .openAdminDefault
        openOnlineStoreHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .openOnlineStoreHotkey) ?? .openOnlineStoreDefault
        openSupportHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .openSupportHotkey) ?? .openSupportDefault
        focusSearchHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .focusSearchHotkey) ?? .focusSearchDefault
        toggleLinkSearchHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .toggleLinkSearchHotkey) ?? .toggleLinkSearchDefault
        openCreateLinkHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .openCreateLinkHotkey) ?? .openCreateLinkDefault
        savedSectionPresets = try c.decodeIfPresent([SavedSectionPreset].self, forKey: .savedSectionPresets) ?? []
        prefersCustomSectionPreset = try c.decodeIfPresent(Bool.self, forKey: .prefersCustomSectionPreset) ?? false
        preferredSavedSectionPresetID = try c.decodeIfPresent(UUID.self, forKey: .preferredSavedSectionPresetID)
    }
}
