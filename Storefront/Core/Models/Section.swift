import Foundation

enum SectionID: String, Codable, CaseIterable, Hashable {
    case products
    case collections
    case themes
    case navigationAndRedirects
    case orders
    case discounts
    case settings
    case apps
    case analytics
    case content
    case customers

    var title: String {
        switch self {
        case .products: return "Products"
        case .collections: return "Collections"
        case .themes: return "Themes"
        case .navigationAndRedirects: return "Navigation"
        case .orders: return "Orders"
        case .discounts: return "Discounts"
        case .settings: return "Store settings"
        case .apps: return "Apps"
        case .analytics: return "Analytics"
        case .content: return "Content"
        case .customers: return "Customers"
        }
    }

    /// Polaris icon asset name (from `@shopify/polaris-icons`, MIT licensed) shown
    /// alongside the card title in the panel.
    var iconName: String {
        switch self {
        case .products: return "ProductIcon"
        case .collections: return "CollectionIcon"
        case .themes: return "ThemeIcon"
        case .navigationAndRedirects: return "MenuIcon"
        case .orders: return "OrderIcon"
        case .discounts: return "DiscountIcon"
        case .settings: return "SettingsIcon"
        case .apps: return "AppsIcon"
        case .analytics: return "ChartVerticalIcon"
        case .content: return "ContentIcon"
        case .customers: return "PersonIcon"
        }
    }

    /// Default display order, matching Shopify's own admin sidebar ordering. Navigation
    /// has no literal top-level equivalent there (it lives under Online Store), so it's
    /// placed next to Themes/Content, the closest real grouping.
    static var defaultOrder: [SectionID] {
        [.orders, .products, .collections, .customers, .discounts, .content, .analytics, .themes, .navigationAndRedirects, .apps, .settings]
    }
}

/// Built-in section layouts for Settings → Sections.
enum SectionPreset: String, CaseIterable, Identifiable, Hashable {
    case `default`
    case storeManager
    case marketer
    case developer

    var id: Self { self }

    var title: String {
        switch self {
        case .default: "Default"
        case .storeManager: "Store manager"
        case .marketer: "Marketer"
        case .developer: "Developer"
        }
    }

    /// Enabled sections in display order for this preset.
    private var enabledHead: [SectionID] {
        switch self {
        case .default:
            return SectionID.defaultOrder
        case .storeManager:
            return [.orders, .customers, .products, .collections, .themes, .apps, .settings]
        case .marketer:
            return [.analytics, .discounts, .products, .collections, .apps, .settings]
        case .developer:
            return [.themes, .content, .products, .collections, .navigationAndRedirects, .apps, .settings]
        }
    }

    /// Full `sectionOrder` (enabled head + disabled tail in `defaultOrder`) and enabled set.
    func layout() -> (order: [SectionID], enabled: Set<SectionID>) {
        let head = enabledHead
        let enabled = Set(head)
        let tail = SectionID.defaultOrder.filter { !enabled.contains($0) }
        return (head + tail, enabled)
    }
}

/// Derived picker selection: built-in, saved user preset, or unsaved Custom.
enum ActiveSectionPreset: Hashable, Identifiable {
    case builtin(SectionPreset)
    case saved(UUID)
    case custom

    var id: String {
        switch self {
        case .builtin(let preset): "builtin-\(preset.rawValue)"
        case .saved(let id): "saved-\(id.uuidString)"
        case .custom: "custom"
        }
    }

    /// Match built-ins first, then the first saved preset with an identical layout, else `.custom`.
    ///
    /// Callers that need a sticky saved selection when a saved layout also matches a
    /// built-in should check `preferredSavedSectionPresetID` before calling this.
    static func match(
        order: [SectionID],
        enabled: Set<SectionID>,
        saved: [SavedSectionPreset]
    ) -> ActiveSectionPreset {
        for preset in SectionPreset.allCases {
            let layout = preset.layout()
            if layout.order == order, layout.enabled == enabled {
                return .builtin(preset)
            }
        }
        if let saved = saved.first(where: { $0.sectionOrder == order && $0.enabledSections == enabled }) {
            return .saved(saved.id)
        }
        return .custom
    }
}

struct LinkRow: Identifiable {
    /// A "New X" action attached to a row and rendered as a trailing "New +" button,
    /// rather than as its own separate row.
    struct CreateAction {
        let path: String
        /// Singular noun for the create tooltip (e.g. "Product" for a Products row).
        let noun: String
    }

    let id: String
    let title: String
    let path: String
    /// Polaris icon asset name shown leading the row's title.
    let iconName: String
    var createAction: CreateAction? = nil
    /// Overrides `path`'s admin.shopify.com templating with a fully-formed external URL
    /// (e.g. the public Shopify App Store, which isn't a per-store admin path).
    var absoluteURL: String? = nil
    /// Whether this row offers an inline search box that appends a query param to its own
    /// `path` — unlike `createAction`, search never needs a different path than the row's,
    /// except for `absoluteSearchURL` rows (e.g. the public App Store) which aren't a
    /// per-store admin path at all.
    var supportsSearch: Bool = false
    /// Overrides the admin.shopify.com/store/<handle> templating for search specifically —
    /// for a row whose search lives at a different, non-per-store URL (the App Store).
    var absoluteSearchURL: String? = nil
    /// Shopify admin pages use `?query=`; the App Store's own search uses `?q=`.
    var searchQueryParamName: String = "query"
    /// Bare lowercase letter that opens this row from the panel (no modifiers).
    var shortcutKey: Character? = nil

    func url(for domain: String) -> URL? {
        if let absoluteURL { return URL(string: absoluteURL) }
        return URL(string: "https://admin.shopify.com/store/\(Store.handle(fromDomain: domain))\(path)")
    }

    func createURL(for domain: String) -> URL? {
        guard let createAction else { return nil }
        return URL(string: "https://admin.shopify.com/store/\(Store.handle(fromDomain: domain))\(createAction.path)")
    }

    func searchURL(for domain: String, query: String) -> URL? {
        guard supportsSearch else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let base = absoluteSearchURL ?? "https://admin.shopify.com/store/\(Store.handle(fromDomain: domain))\(path)"
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: searchQueryParamName, value: trimmed)]
        return components?.url
    }
}

/// The fixed catalog of admin deep links shown per section.
enum StaticLinkCatalog {
    /// The catalog never changes, but `rows(for:)` sits in very hot paths — once per
    /// section card per panel render, and once per hover event just to bounds-check a
    /// row index. Build every section's array once and hand back the shared copy.
    private static let rowsBySection: [SectionID: [LinkRow]] = Dictionary(
        uniqueKeysWithValues: SectionID.allCases.map { ($0, buildRows(for: $0)) }
    )

    static func rows(for section: SectionID) -> [LinkRow] {
        rowsBySection[section] ?? []
    }

    /// First row in `sections` bound to `key`, with its section and index in that section.
    static func row(forShortcut key: Character, in sections: [SectionID]) -> (section: SectionID, rowIndex: Int, row: LinkRow)? {
        for section in sections {
            if let index = rows(for: section).firstIndex(where: { $0.shortcutKey == key }) {
                return (section, index, rows(for: section)[index])
            }
        }
        return nil
    }

    private static func buildRows(for section: SectionID) -> [LinkRow] {
        switch section {
        case .products:
            return [
                LinkRow(id: "products.all", title: "Products", path: "/products", iconName: "ProductIcon", createAction: .init(path: "/products/new", noun: "Product"), supportsSearch: true, shortcutKey: "p"),
                LinkRow(id: "products.inventory", title: "Inventory", path: "/products/inventory", iconName: "InventoryIcon", supportsSearch: true),
                LinkRow(id: "products.giftCards", title: "Gift Cards", path: "/gift_cards", iconName: "GiftCardIcon"),
            ]
        case .collections:
            return [
                LinkRow(id: "collections.all", title: "Collections", path: "/collections", iconName: "CollectionIcon", createAction: .init(path: "/collections/new", noun: "Collection"), supportsSearch: true, shortcutKey: "c"),
            ]
        case .themes:
            return [
                LinkRow(id: "themes.library", title: "Theme library", path: "/themes", iconName: "ThemeTemplateIcon", shortcutKey: "t"),
                LinkRow(id: "themes.rollouts", title: "Rollouts", path: "/rollouts", iconName: "RocketIcon"),
                LinkRow(id: "themes.preferences", title: "Online Store Preferences", path: "/online_store/preferences", iconName: "SettingsIcon"),
            ]
        case .navigationAndRedirects:
            return [
                LinkRow(id: "navigation.all", title: "Menus", path: "/menus", iconName: "ListBulletedIcon", createAction: .init(path: "/menus/new", noun: "Menu"), shortcutKey: "n"),
                LinkRow(id: "redirects.all", title: "Redirects", path: "/content/redirects", iconName: "DomainRedirectIcon", createAction: .init(path: "/content/redirects/new", noun: "Redirect"), supportsSearch: true, shortcutKey: "r"),
            ]
        case .orders:
            return [
                LinkRow(id: "orders.all", title: "Orders", path: "/orders", iconName: "OrderIcon"),
                LinkRow(id: "orders.unfulfilled", title: "Unfulfilled", path: "/orders?query=fulfillment_status%3Aunfulfilled", iconName: "OrderUnfulfilledIcon"),
                LinkRow(id: "orders.drafts", title: "Drafts", path: "/draft_orders", iconName: "OrderDraftIcon"),
                LinkRow(id: "orders.abandoned", title: "Abandoned checkouts", path: "/checkouts", iconName: "CartAbandonedIcon"),
            ]
        case .discounts:
            return [
                LinkRow(id: "discounts.all", title: "Discounts", path: "/discounts", iconName: "DiscountIcon", createAction: .init(path: "/discounts/new", noun: "Discount"), supportsSearch: true, shortcutKey: "d"),
            ]
        case .settings:
            return [
                LinkRow(id: "settings.general", title: "General", path: "/settings/general", iconName: "SettingsIcon", shortcutKey: "g"),
                LinkRow(id: "settings.payments", title: "Payments", path: "/settings/payments", iconName: "PaymentIcon"),
                LinkRow(id: "settings.checkout", title: "Checkout", path: "/settings/checkout", iconName: "CreditCardIcon"),
                LinkRow(id: "settings.shipping", title: "Shipping", path: "/settings/shipping", iconName: "DeliveryIcon"),
                LinkRow(id: "settings.domains", title: "Domains", path: "/settings/domains", iconName: "DomainIcon"),
                LinkRow(id: "settings.markets", title: "Markets", path: "/settings/markets", iconName: "MarketsIcon"),
                LinkRow(id: "settings.notifications", title: "Notifications", path: "/settings/notifications", iconName: "NotificationIcon"),
            ]
        case .apps:
            return [
                LinkRow(id: "apps.installed", title: "Installed apps", path: "/settings/apps", iconName: "AppsIcon"),
                LinkRow(id: "apps.store", title: "App store", path: "", iconName: "StoreIcon", absoluteURL: "https://apps.shopify.com/", supportsSearch: true, absoluteSearchURL: "https://apps.shopify.com/search", searchQueryParamName: "q"),
            ]
        case .analytics:
            return [
                LinkRow(id: "analytics.dashboard", title: "Dashboards", path: "/analytics", iconName: "ChartVerticalIcon"),
                LinkRow(id: "analytics.reports", title: "Reports", path: "/analytics/reports", iconName: "ChartLineIcon", supportsSearch: true),
                LinkRow(id: "analytics.live", title: "Live view", path: "/analytics/live", iconName: "LiveIcon"),
                LinkRow(id: "analytics.agentic", title: "Agentic", path: "/apps/agentic", iconName: "AgenticIcon"),
            ]
        case .content:
            return [
                LinkRow(id: "content.pages", title: "Pages", path: "/pages", iconName: "PageIcon", createAction: .init(path: "/pages/new", noun: "Page"), supportsSearch: true, shortcutKey: "w"),
                LinkRow(id: "content.blogs", title: "Blogs", path: "/content/blogs", iconName: "BlogIcon", createAction: .init(path: "/content/blogs/new", noun: "Blog"), supportsSearch: true, shortcutKey: "b"),
                LinkRow(id: "content.blog", title: "Blog posts", path: "/content/articles", iconName: "BlogIcon", createAction: .init(path: "/content/articles/new", noun: "Blog post"), supportsSearch: true),
                LinkRow(id: "content.files", title: "Files", path: "/content/files", iconName: "FileIcon", supportsSearch: true, shortcutKey: "f"),
                LinkRow(id: "content.metafields", title: "Metafields", path: "/settings/custom_data", iconName: "MetaobjectListIcon", shortcutKey: "m"),
            ]
        case .customers:
            return [
                LinkRow(id: "customers.all", title: "Customers", path: "/customers", iconName: "PersonIcon"),
                LinkRow(id: "customers.segments", title: "Segments", path: "/customers/segments", iconName: "PersonSegmentIcon"),
                LinkRow(id: "customers.companies", title: "Companies", path: "/companies", iconName: "WorkIcon"),
            ]
        }
    }
}
