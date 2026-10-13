import SwiftUI
import AppKit

/// Resolved chrome for the menu bar widget — drives fills, borders, and shadows.
enum WidgetChrome: Equatable {
    /// Native Liquid Glass / vibrancy.
    case macOSGlass
    /// Native opaque elevated surfaces.
    case macOSOpaque
    /// Shopify Admin / Polaris flat surfaces.
    case shopify

    static func current(settings: AppSettings) -> WidgetChrome {
        if settings.widgetThemePreference.isShopify { return .shopify }
        return settings.opaqueMenuBarWidget ? .macOSOpaque : .macOSGlass
    }

    var isShopify: Bool { self == .shopify }
    var isOpaque: Bool { self != .macOSGlass }

    /// Polaris uses circular arcs; macOS chrome keeps continuous squircles.
    var cornerStyle: RoundedCornerStyle { isShopify ? .circular : .continuous }
}

enum Theme {
    static let errorDot = Color(hex: "c0562c")
    /// Hotkey recorder “listening” label.
    static let recordingText = Color.adaptive(light: Color(hex: "d4785a"), dark: Color(hex: "e8a090"))

    static let hoverFill = Color.adaptive(light: .black.opacity(0.045), dark: .white.opacity(0.07))
    static let controlFill = Color.adaptive(light: .black.opacity(0.07), dark: .white.opacity(0.1))
    /// Hairline around an active row filled with `controlFill`, a step darker than it.
    static let controlBorder = Color.adaptive(light: .black.opacity(0.1), dark: .white.opacity(0.14))
    static let searchFill = Color.adaptive(light: .black.opacity(0.055), dark: .white.opacity(0.08))
    static let hairline = Color.adaptive(light: .black.opacity(0.07), dark: .white.opacity(0.08))
    static let divider = Color.adaptive(light: .black.opacity(0.08), dark: .white.opacity(0.08))
    static let borderColor = Color.adaptive(light: .black.opacity(0.12), dark: .white.opacity(0.1))
    /// Light plate behind store favicons in dark appearance so dark logos stay legible.
    static let faviconPlate = Color.adaptive(light: .clear, dark: .white)
    /// Matching AppKit fill opacity for menu-bar favicon drawing (dark appearance only).
    static let faviconPlateDarkOpacity: CGFloat = 1

    /// Flat card border — the fill comes from `SidebarGlassBackground` for panel section cards.
    static let cardBorder = Color.adaptive(light: .black.opacity(0.08), dark: .white.opacity(0.07))

    /// Opaque card/list background for the Settings window (not the vibrancy-backed
    /// panel, whose cards are drawn by `SidebarGlassBackground`).
    /// `.controlBackgroundColor` is the system-adaptive content-area color AppKit
    /// windows use, so it automatically flips with light/dark appearance.
    static let settingsCardFill = Color(nsColor: .controlBackgroundColor)

    /// Opaque menu bar widget body fill (Liquid Glass off).
    static let panelOpaqueFill = Color(nsColor: .windowBackgroundColor)
    /// Opaque elevated surfaces for the floating rail and section cards (Liquid Glass off).
    static let panelOpaqueElevatedFill = Color(nsColor: .controlBackgroundColor)
    /// Soft drop shadow for opaque elevated rail/cards.
    static let panelElevatedShadow = Color.adaptive(light: .black.opacity(0.08), dark: .black.opacity(0.28))

    static let textPrimary = Color.adaptive(light: Color(hex: "111111"), dark: Color(hex: "f2f2f4"))
    static let textBody = Color.adaptive(light: .black.opacity(0.82), dark: .white.opacity(0.82))
    static let textSecondary = Color.adaptive(light: .black.opacity(0.5), dark: .white.opacity(0.5))
    static let textMeta40 = Color.adaptive(light: .black.opacity(0.4), dark: .white.opacity(0.4))
    static let textMeta36 = Color.adaptive(light: .black.opacity(0.36), dark: .white.opacity(0.36))
    static let textMeta30 = Color.adaptive(light: .black.opacity(0.3), dark: .white.opacity(0.35))
    static let textMeta25 = Color.adaptive(light: .black.opacity(0.25), dark: .white.opacity(0.3))

    /// Shopify Admin / Polaris tokens (light only — matches admin Settings).
    enum Shopify {
        /// Page / panel body (white admin page surface behind cards).
        static let pageBackground = Color.white
        /// Card / sidebar surface.
        static let surface = Color.white
        /// Default border (`border-secondary`).
        static let border = Color(hex: "e3e3e3")
        /// Softer hairlines inside surfaces.
        static let hairline = Color(hex: "ebebeb")
        /// Nav / row hover + selected fill.
        static let hoverFill = Color(hex: "f1f1f1")
        /// Search field fill (white with border, not a gray wash).
        static let searchFill = Color.white
        static let searchBorder = Color(hex: "c9cccf")
        static let textPrimary = Color(hex: "303030")
        /// Card headings and card link icons.
        static let textStrong = Color(hex: "101010")
        /// Card row search / "+" glyphs at rest.
        static let iconSecondary = Color(hex: "4a4a4a")
        /// Active (hovered / arrow-focused) card link row.
        static let rowHighlightFill = Color(hex: "f7f7f7")
        /// Hairline around the active card link row, a step darker than its fill.
        static let rowHighlightBorder = Color(hex: "ebebeb")
        static let textSecondary = Color(hex: "616161")
        static let textMeta = Color(hex: "8a8a8a")
        /// Copy-confirmation checkmark. Polaris `color-icon-success`.
        static let iconSuccess = Color(hex: "29845a")
        /// Dark admin nav column (new Shopify admin) — fixed, independent of appearance.
        enum Sidebar {
            static let fill = Color(hex: "0a0a0a")
            /// AppKit `fill` for the popover frame, so the beak matches the sidebar.
            static var fillNSColor: NSColor { NSColor(srgbRed: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1) }
            static let textPrimary = Color.white
            /// Non-selected nav item label (admin settings nav `#dcdcdc`).
            static let textItem = Color(hex: "dcdcdc")
            static let textSecondary = Color.white.opacity(0.72)
            static let textMeta = Color.white.opacity(0.55)
            static let searchFill = Color.white.opacity(0.19)
            /// Search icon, placeholder, and shortcut hint (admin search pill `#a6a6a6`).
            static let searchText = Color(hex: "a6a6a6")
            static let hoverFill = Color.white.opacity(0.06)
            static let selectedFill = Color.white.opacity(0.11)
            static let hairline = Color.white.opacity(0.1)
        }
    }

    static let panelSize = CGSize(width: 640, height: 520)
    /// Full-height sidebar, flush with the panel’s top / leading / bottom edges.
    static let railWidth: CGFloat = 220
    /// Shopify detail sheet’s corners, revealing the dark sidebar behind them.
    static let contentSheetCornerRadius: CGFloat = 12
    /// Gap between the Shopify detail sheet and the panel’s top / trailing / bottom edges.
    static let contentSheetInset: CGFloat = 4
    /// Floating / under-mouse panel chrome corner radius (matches `AppDelegate` window mask).
    static let floatingPanelCornerRadius: CGFloat = 14

    /// Detached floating window (under mouse, or menu bar icon hidden).
    static func isFloatingPanel(settings: AppSettings) -> Bool {
        !settings.showInMenuBar || settings.openUnderMouse
    }

    /// Distance from the panel’s top-leading origin to the center of the first
    /// store row in the rail (search + “N Stores” + dividers + half a row).
    /// Used to open the detached floating panel under the pointer.
    static var floatingPanelFirstStoreRowCenter: CGPoint {
        // Vertical stack inside the rail (see StoreRailView):
        // rail top pad + search(26) + search bottom(7) + spacing(1)
        // + stores label(~14) + label bottom(4) + spacing(1) + divider(1) + spacing(1)
        // + scroll top pad(4) + half of first row (~29/2).
        let y =
            8 // rail content top padding
            + 26 // search field height
            + 7 // search bottom padding
            + 1 // VStack spacing
            + 14 // “N Stores” label row
            + 4 // label bottom padding
            + 1 // spacing
            + 1 // divider
            + 1 // spacing
            + 4 // scroll top padding
            + 14.5 // center of first store row
        let x = railWidth / 2
        return CGPoint(x: x, y: y)
    }
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Bundled Shopify Inter Variable face (Shopify theme). Weight via the `wght` axis.
    /// Family name is versioned in the font's `name` table — update with the TTF.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Shopify Inter Beta 0.29", size: size).weight(weight)
    }

    /// Panel UI type — Inter under Shopify, system otherwise.
    static func panel(_ size: CGFloat, weight: Font.Weight = .regular, shopify: Bool) -> Font {
        shopify ? .inter(size, weight: weight) : .system(size: size, weight: weight)
    }
}

extension View {
    /// Border + elevation for the floating store rail and section cards.
    ///
    /// Shopify has no stroke — the tight 2px shadow layer draws the edge.
    @ViewBuilder
    func floatingCardChrome(
        chrome: WidgetChrome,
        cornerRadius: CGFloat,
        macOSShadowRadius: CGFloat,
        macOSShadowY: CGFloat
    ) -> some View {
        switch chrome {
        case .shopify:
            self.shopifyCardShadow(cornerRadius: cornerRadius)
        case .macOSOpaque:
            self
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                }
                .shadow(color: Theme.panelElevatedShadow, radius: macOSShadowRadius, y: macOSShadowY)
        case .macOSGlass:
            self
        }
    }

    /// New admin card elevation:
    /// `rgba(0,0,0,.24) 0 0 2px, rgba(0,0,0,.02) 0 2px 12px, rgba(0,0,0,.02) 0 4px 16px, rgba(0,0,0,.02) 0 4px 48px`.
    /// One shape per layer — chained `.shadow` modifiers would shadow each other.
    /// SwiftUI `radius` ≈ CSS blur / 2.
    func shopifyCardShadow(cornerRadius: CGFloat) -> some View {
        let layers: [(opacity: Double, radius: CGFloat, y: CGFloat)] = [
            (0.24, 1, 0),
            (0.02, 6, 2),
            (0.02, 8, 4),
            (0.02, 24, 4),
        ]
        return background {
            ZStack {
                ForEach(layers.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.Shopify.surface)
                        .shadow(color: .black.opacity(layers[i].opacity), radius: layers[i].radius, y: layers[i].y)
                }
            }
        }
    }
}

/// Raised dark-nav surface (admin search pill / selected nav item):
/// `rgba(255,255,255,.02) 0 0 0 1px inset, rgba(255,255,255,.06) 0 1px 1px inset,
/// rgba(255,255,255,.06) 0 0 12px 1px inset, rgba(0,0,0,.1) 0 1px 2px, rgba(0,0,0,.1) 0 0 0 1px`.
struct ShopifySidebarRaisedSurface: View {
    let fill: Color
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        shape
            .fill(
                fill
                    .shadow(.inner(color: .white.opacity(0.06), radius: 0.5, y: 1))
                    .shadow(.inner(color: .white.opacity(0.06), radius: 6))
            )
            .overlay { shape.strokeBorder(Color.white.opacity(0.02), lineWidth: 1) }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius + 1, style: .circular)
                    .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                    .padding(-1)
            }
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
    }
}

extension Color {
    /// A color that automatically resolves to `light` or `dark` based on the current
    /// system/window appearance, without needing `@Environment(\.colorScheme)` threaded
    /// through every view.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
}
