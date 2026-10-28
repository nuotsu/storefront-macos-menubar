import SwiftUI
import AppKit

struct Store: Identifiable, Codable, Equatable {
    let id: UUID
    var accountID: UUID
    var myshopifyDomain: String
    var displayName: String
    var colorHex: String
    var isVisible: Bool
    var sortOrder: Int
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        accountID: UUID,
        myshopifyDomain: String,
        displayName: String,
        colorHex: String,
        isVisible: Bool = true,
        sortOrder: Int = 0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.myshopifyDomain = myshopifyDomain
        self.displayName = displayName
        self.colorHex = colorHex
        self.isVisible = isVisible
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
    }

    var color: Color {
        Color(hex: colorHex)
    }

    /// Automatic a11y text color for content drawn on top of this store's accent color —
    /// black on light accents, white on dark ones, via a standard luma calculation.
    var accentTextColor: Color {
        let (r, g, b) = HexColor.components(colorHex)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        return luma > 150 ? .black : .white
    }

    var isWhiteAccent: Bool {
        let (r, g, b) = HexColor.components(colorHex)
        return r == 255 && g == 255 && b == 255
    }

    var initials: String {
        let words = displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Whether this store should appear for a rail search query: display-name substring
    /// match, or word-initial abbreviation (e.g. `BFG` → "Blue Falcon Golf").
    func matchesSearchQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if displayName.localizedCaseInsensitiveContains(trimmed) { return true }
        let abbreviation = Self.searchAbbreviation(from: displayName)
        return abbreviation.localizedCaseInsensitiveContains(trimmed)
    }

    /// First alphanumeric character of each token in `name`, joined (e.g. "Blue-Falcon Golf" → "BFG").
    private static func searchAbbreviation(from name: String) -> String {
        var result = ""
        var inToken = false
        for character in name {
            if character.isLetter || character.isNumber {
                if !inToken {
                    result.append(character)
                    inToken = true
                }
            } else {
                inToken = false
            }
        }
        return result
    }

    /// Accent rotation for new stores (Add Store sheet and CSV rows with no Color column).
    private static let accentPalette = ["1f6f4a", "c07a2c", "3a6ea8", "7a4b8c", "4a7a5c", "a8563a", "5c9fd6", "a37bb8"]

    /// Default accent for the store that will sit at `index` in the list.
    static func defaultColorHex(forIndex index: Int) -> String {
        accentPalette[index % accentPalette.count]
    }

    static let domainSuffix = ".myshopify.com"

    /// The store "handle" used in admin.shopify.com URLs, i.e. the domain minus ".myshopify.com".
    static func handle(fromDomain domain: String) -> String {
        domain.replacingOccurrences(of: domainSuffix, with: "")
    }

    /// A user-typed domain coerced to a full `<handle>.myshopify.com`. Accepts either a
    /// bare handle or a complete domain.
    ///
    /// Behaviour is deliberately identical to the three copies this replaced, down to
    /// `replacingOccurrences` stripping *every* occurrence of the suffix — so an input
    /// like `a.myshopify.com.b` normalizes oddly. Worth fixing, but as its own change.
    static func normalizedDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasSuffix(domainSuffix) else { return trimmed }
        return trimmed.replacingOccurrences(of: domainSuffix, with: "") + domainSuffix
    }

    var handle: String { Store.handle(fromDomain: myshopifyDomain) }

    var adminURL: URL? { URL(string: "https://admin.shopify.com/store/\(handle)") }
    var shopURL: URL? { URL(string: "https://\(myshopifyDomain)") }
    var supportURL: URL? { URL(string: "https://help.shopify.com") }
}

/// The one place a `"rrggbb"` / `"#rrggbb"` string is parsed. Previously this same
/// Scanner routine existed three times, including once inside a file about text-field
/// tuning, where nobody would look for it.
enum HexColor {
    /// Red, green and blue in `0...255`.
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        return (
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        )
    }
}

extension Color {
    init(hex: String) {
        let (r, g, b) = HexColor.components(hex)
        self.init(red: r / 255, green: g / 255, blue: b / 255)
    }

    /// Converts this color to a "rrggbb" hex string, for persisting user-picked colors.
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }

    /// This color's opaque RGB, as if drawn at `alpha` over `background`.
    func composited(over background: Color, alpha: Double) -> Color {
        let fg = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let bg = NSColor(background).usingColorSpace(.deviceRGB) ?? NSColor(background)
        return Color(
            red: alpha * fg.redComponent + (1 - alpha) * bg.redComponent,
            green: alpha * fg.greenComponent + (1 - alpha) * bg.greenComponent,
            blue: alpha * fg.blueComponent + (1 - alpha) * bg.blueComponent
        )
    }

    /// WCAG relative luminance (0...1), used for a11y contrast checks.
    private var relativeLuminance: Double {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(Double(nsColor.redComponent))
            + 0.7152 * channel(Double(nsColor.greenComponent))
            + 0.0722 * channel(Double(nsColor.blueComponent))
    }

    /// WCAG contrast ratio (1...21) between this color and another, both treated as opaque.
    func contrastRatio(with other: Color) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        let (lighter, darker) = l1 > l2 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Approximate panel surface for a11y contrast checks. Cards are vibrancy-backed so
    /// the true backdrop isn't knowable; these match the constants historically used by
    /// `pillBackground`.
    static func panelBackdrop(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.97)
    }

    /// This color's own tinted-pill background (this color at `alpha` over the panel's
    /// light/dark backdrop) — used for accent "chip" style buttons like the "+" create
    /// actions and, per this color, the text color to draw on top of it.
    func pillBackground(colorScheme: ColorScheme, alpha: Double = 0.12) -> Color {
        composited(over: Self.panelBackdrop(colorScheme: colorScheme), alpha: alpha)
    }

    /// Text color for this color's own tinted pill background — falls back to black
    /// (light mode) or white (dark mode) when this color itself doesn't contrast enough
    /// against its own tint (e.g. a pale color washing out on a near-white light-mode pill).
    func pillTextColor(colorScheme: ColorScheme, alpha: Double = 0.12) -> Color {
        let fallback: Color = colorScheme == .dark ? .white : .black
        let background = pillBackground(colorScheme: colorScheme, alpha: alpha)
        return contrastRatio(with: background) >= 3 ? self : fallback
    }

    /// Whether this color reads clearly enough against the panel surface to be used as a
    /// tint on it (e.g. a caret) — a dark navy in dark mode or a pale yellow in light mode
    /// does not.
    func contrastsWithPanelSurface(colorScheme: ColorScheme, minimumRatio: Double = 3) -> Bool {
        contrastRatio(with: Self.panelBackdrop(colorScheme: colorScheme)) >= minimumRatio
    }
}

