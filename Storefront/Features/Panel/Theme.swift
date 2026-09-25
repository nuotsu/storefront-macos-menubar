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
        /// Page / panel body (`bg-surface-secondary`).
        static let pageBackground = Color(hex: "f1f1f1")
        /// Card / sidebar surface.
        static let surface = Color.white
        /// Default border (`border-secondary`).
        static let border = Color(hex: "e3e3e3")
        /// Softer hairlines inside surfaces.
        static let hairline = Color(hex: "ebebeb")
        /// Nav / row hover + selected fill.
        static let hoverFill = Color(hex: "f1f1f1")
        static let controlFill = Color(hex: "f1f1f1")
        /// Search field fill (white with border, not a gray wash).
        static let searchFill = Color.white
        static let searchBorder = Color(hex: "c9cccf")
        static let textPrimary = Color(hex: "303030")
        static let textSecondary = Color(hex: "616161")
        static let textMeta = Color(hex: "8a8a8a")
        /// AppKit fill for the hosting view under SwiftUI.
        static var pageBackgroundNSColor: NSColor { NSColor(hex: "f1f1f1") }

        /// Soft 1px ring on section cards.
        static let cardRing = Color(hex: "e2e2e2")

        /// Dark admin nav column (new Shopify admin) — fixed, independent of appearance.
        enum Sidebar {
            static let fill = Color(hex: "1a1a1a")
            static let textPrimary = Color.white
            static let textSecondary = Color.white.opacity(0.72)
            static let textMeta = Color.white.opacity(0.55)
            static let searchFill = Color.white.opacity(0.08)
            static let searchBorder = Color.white.opacity(0.14)
            static let hoverFill = Color.white.opacity(0.08)
            static let selectedFill = Color.white.opacity(0.14)
            static let hairline = Color.white.opacity(0.1)
        }
    }

    static let panelSize = CGSize(width: 560, height: 520)
    /// Full-height sidebar, flush with the panel’s top / leading / bottom edges.
    static let railWidth: CGFloat = 186
    /// Shopify detail sheet’s leading corners, revealing the dark sidebar behind them.
    static let contentSheetCornerRadius: CGFloat = 12
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

    /// Bundled Inter Variable face (Shopify theme). Weight via the `wght` axis.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("InterVariable", size: size).weight(weight)
    }

    /// Panel UI type — Inter under Shopify, system otherwise.
    static func panel(_ size: CGFloat, weight: Font.Weight = .regular, shopify: Bool) -> Font {
        shopify ? .inter(size, weight: weight) : .system(size: size, weight: weight)
    }
}

extension View {
    /// Border + elevation for the floating store rail and section cards.
    ///
    /// Shopify uses Polaris’s layered card shadow (approx.):
    /// `rgba(0,0,0,0.03) 0 5px 5px -2.5px, … , rgba(0,0,0,0.06) 0 0 0 1px`.
    @ViewBuilder
    func floatingCardChrome(
        chrome: WidgetChrome,
        cornerRadius: CGFloat,
        macOSShadowRadius: CGFloat,
        macOSShadowY: CGFloat
    ) -> some View {
        switch chrome {
        case .shopify:
            self
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                        .strokeBorder(Theme.Shopify.cardRing, lineWidth: 1)
                }
                .shopifyCardShadow()
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

    /// Soft stacked shadows matching Polaris card elevation (spread approximated away).
    func shopifyCardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.014), radius: 1.75, y: 3)
            .shadow(color: .black.opacity(0.01), radius: 1, y: 2)
            .shadow(color: .black.opacity(0.01), radius: 0.6, y: 1.25)
            .shadow(color: .black.opacity(0.014), radius: 0.3, y: 0.5)
            .shadow(color: .black.opacity(0.018), radius: 0.15, y: 0.25)
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
