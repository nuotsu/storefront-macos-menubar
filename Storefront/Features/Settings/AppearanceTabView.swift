import AppKit
import SwiftUI

struct AppearanceTabView: View {
    @Environment(AppState.self) private var appState

    private var isShopifyTheme: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroupedCard {
                    SettingsGroupedRow(
                        "Menu bar icon",
                        alignment: .top
                    ) {
                        MenuBarIconPreferencePicker(
                            selection: Binding(
                                get: { appState.settings.menuBarIconPreference },
                                set: { appState.setMenuBarIconPreference($0) }
                            )
                        )
                        .frame(width: IconSettingsMetrics.controlWidth)
                        .layoutPriority(1)
                    }
                    .padding(.vertical, 6)

                    SettingsGroupedDivider()

                    SettingsGroupedRow(
                        "App Icon",
                        alignment: .top
                    ) {
                        AppIconThumbnailPicker(
                            selection: Binding(
                                get: { appState.settings.appIconPreference },
                                set: { appState.setAppIconPreference($0) }
                            )
                        )
                        .frame(width: IconSettingsMetrics.controlWidth)
                        .layoutPriority(1)
                    }
                    .padding(.vertical, 6)
                }

                SettingsGroupedCard {
                    SettingsGroupedRow("Theme", alignment: .top) {
                        WidgetThemeThumbnailPicker(
                            selection: Binding(
                                get: { appState.settings.widgetThemePreference },
                                set: { appState.setWidgetThemePreference($0) }
                            )
                        )
                    }
                    .padding(.vertical, 6)

                    SettingsGroupedDivider()

                    SettingsGroupedRow("Appearance", alignment: .top) {
                        AppearanceThumbnailPicker(
                            selection: Binding(
                                get: { appState.settings.appearancePreference },
                                set: { appState.setAppearancePreference($0) }
                            )
                        )
                        .disabled(isShopifyTheme)
                    }
                    .padding(.vertical, 6)
                    .opacity(isShopifyTheme ? 0.4 : 1)
                    .allowsHitTesting(!isShopifyTheme)

                    SettingsGroupedDivider()

                    SettingsGroupedRow(
                        "Widget background",
                        alignment: .top
                    ) {
                        PanelBackgroundThumbnailPicker(
                            opaque: Binding(
                                get: { appState.settings.opaqueMenuBarWidget },
                                set: { appState.setOpaqueMenuBarWidget($0) }
                            )
                        )
                        .disabled(isShopifyTheme)
                    }
                    .padding(.vertical, 6)
                    .opacity(isShopifyTheme ? 0.4 : 1)
                    .allowsHitTesting(!isShopifyTheme)
                }

                SettingsDocsFooter()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .settingsTopScrollEdgeBlur()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared trailing width so Menu bar icon + App Icon controls share one column.
private enum IconSettingsMetrics {
    /// Four 44pt tiles + padding(2) each, with 10pt gaps — matches App Icon row.
    static let controlWidth: CGFloat = 206
}

/// Split controls: Outline/Filled style + Bag/Cart/Store/Shopify icon chips.
private struct MenuBarIconPreferencePicker: View {
    @Binding var selection: MenuBarIconPreference

    /// Shopify has only one form — the Outline/Filled style doesn't apply to it.
    private var isShopifySelected: Bool {
        selection.family == .shopify
    }

    private var filledBinding: Binding<Bool> {
        Binding(
            get: { selection.isFilled },
            set: { selection = .preference(family: selection.family, filled: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Style", selection: filledBinding) {
                Text("Outline").tag(false)
                Text("Filled").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .disabled(isShopifySelected)
            .opacity(isShopifySelected ? 0.4 : 1)
            .allowsHitTesting(!isShopifySelected)

            HStack(spacing: 10) {
                ForEach(MenuBarIconPreference.Family.displayOrder) { family in
                    let option = MenuBarIconPreference.preference(
                        family: family,
                        filled: selection.isFilled
                    )
                    Button {
                        selection = option
                    } label: {
                        MenuBarIconChip(
                            preference: option,
                            title: family.title,
                            isSelected: selection.family == family
                        )
                    }
                    .buttonStyle(.plain)
                    .help(family.title)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MenuBarIconChip: View {
    let preference: MenuBarIconPreference
    let title: String
    let isSelected: Bool

    private let size: CGFloat = 32
    private let cornerRadius: CGFloat = 7
    private let ringInset: CGFloat = 2

    @ViewBuilder
    private var glyph: some View {
        if let symbolName = preference.systemSymbolName {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        } else if let assetName = preference.assetName {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            glyph
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .padding(ringInset)
                .overlay {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: cornerRadius + ringInset,
                            style: .continuous
                        )
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }

            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
        }
        .contentShape(Rectangle())
    }
}

/// macOS vs Shopify theme thumbnails.
private struct WidgetThemeThumbnailPicker: View {
    @Binding var selection: WidgetThemePreference

    var body: some View {
        HStack(spacing: SettingsThumbnailMetrics.spacing) {
            ForEach(WidgetThemePreference.displayOrder) { option in
                Button {
                    selection = option
                } label: {
                    SettingsThumbnailChrome(
                        title: option.title,
                        isSelected: selection == option
                    ) {
                        WidgetThemePreview(theme: option)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// System Settings–style Auto / Light / Dark thumbnails with a blue selection ring.
private struct AppearanceThumbnailPicker: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        HStack(spacing: SettingsThumbnailMetrics.spacing) {
            ForEach(AppearancePreference.displayOrder) { option in
                Button {
                    selection = option
                } label: {
                    SettingsThumbnailChrome(
                        title: option.title,
                        isSelected: selection == option
                    ) {
                        AppearanceDesktopPreview(style: option)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Auto / Light / Dark app icon tiles (cmux-style overlapping Auto preview).
private struct AppIconThumbnailPicker: View {
    @Binding var selection: AppIconPreference

    private let previewSize: CGFloat = 40
    private let autoIconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppIconPreference.displayOrder) { option in
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 5) {
                        Group {
                            if option == .system {
                                ZStack {
                                    // Dark behind; Light on top (leading).
                                    appIconImage("AppIconDark")
                                        .frame(width: autoIconSize, height: autoIconSize)
                                        .offset(x: 8)
                                    appIconImage("AppIconLight")
                                        .frame(width: autoIconSize, height: autoIconSize)
                                        .offset(x: -8)
                                }
                                .frame(width: previewSize, height: previewSize)
                            } else {
                                appIconImage(option.imageName)
                                    .frame(width: previewSize, height: previewSize)
                            }
                        }
                        .padding(2)
                        .overlay {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            }
                        }

                        Text(option.title)
                            .font(.system(size: 10.5, weight: selection == option ? .semibold : .regular))
                            .foregroundStyle(selection == option ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func appIconImage(_ name: String) -> some View {
        if let image = NSImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
        }
    }
}

/// Liquid Glass vs Opaque thumbnails for the menu bar widget chrome.
private struct PanelBackgroundThumbnailPicker: View {
    @Binding var opaque: Bool

    private var options: [(opaque: Bool, title: String)] {
        [(false, "Liquid Glass"), (true, "Opaque")]
    }

    var body: some View {
        HStack(spacing: SettingsThumbnailMetrics.spacing) {
            ForEach(options, id: \.title) { option in
                Button {
                    opaque = option.opaque
                } label: {
                    SettingsThumbnailChrome(
                        title: option.title,
                        isSelected: opaque == option.opaque
                    ) {
                        PanelBackgroundPreview(opaque: option.opaque)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private enum SettingsThumbnailMetrics {
    static let spacing: CGFloat = 14
    static let previewSize = CGSize(width: 64, height: 44)
    static let cornerRadius: CGFloat = 7
    static let ringInset: CGFloat = 2.5
}

/// Shared System Settings–style preview tile: framed thumbnail + caption + accent ring.
private struct SettingsThumbnailChrome<Preview: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        VStack(spacing: 6) {
            preview()
                .frame(
                    width: SettingsThumbnailMetrics.previewSize.width,
                    height: SettingsThumbnailMetrics.previewSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: SettingsThumbnailMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: SettingsThumbnailMetrics.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                .padding(SettingsThumbnailMetrics.ringInset)
                .overlay {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: SettingsThumbnailMetrics.cornerRadius
                                + SettingsThumbnailMetrics.ringInset,
                            style: .continuous
                        )
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    }
                }

            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
        }
        .contentShape(Rectangle())
    }
}

/// Mini panel mock for Theme: macOS glass vs Shopify Polaris.
private struct WidgetThemePreview: View {
    let theme: WidgetThemePreference

    var body: some View {
        switch theme {
        case .macOS:
            PanelBackgroundPreview(opaque: false)
        case .shopify:
            ShopifyThemePreview()
        }
    }
}

/// Flat Polaris-style mini panel: gray page + white bordered rail/cards.
private struct ShopifyThemePreview: View {
    var body: some View {
        ZStack {
            Theme.Shopify.pageBackground

            HStack(alignment: .top, spacing: 3) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Theme.Shopify.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(Theme.Shopify.border, lineWidth: 0.5)
                    }
                    .frame(width: 16)
                    .overlay(alignment: .top) {
                        VStack(spacing: 2) {
                            Capsule()
                                .fill(Color.black.opacity(0.18))
                                .frame(width: 10, height: 2.5)
                            Capsule()
                                .fill(Color.black.opacity(0.12))
                                .frame(width: 10, height: 2.5)
                        }
                        .padding(.top, 4)
                    }

                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.Shopify.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Theme.Shopify.border, lineWidth: 0.5)
                            }
                            .frame(height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
        }
    }
}

/// Mini panel mock: wallpaper + floating rail/cards — glass wash vs solid elevated chrome.
private struct PanelBackgroundPreview: View {
    let opaque: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    /// Solid panel body — slightly darker in dark so elevated chrome can read.
    private var opaqueBodyFill: Color {
        Color.adaptive(
            light: Color(nsColor: .windowBackgroundColor),
            dark: Color(white: 0.13)
        )
    }

    /// Elevated rail/cards — brighter in dark for contrast against the body.
    private var opaqueElevatedFill: Color {
        Color.adaptive(
            light: Color(nsColor: .controlBackgroundColor),
            dark: Color(white: 0.28)
        )
    }

    /// Frosted panel wash — light glass in Light, dark glass when Appearance is Dark.
    private var glassBodyFill: Color {
        Color.adaptive(
            light: Color.white.opacity(0.55),
            dark: Color.white.opacity(0.14)
        )
    }

    private var glassElevatedFill: Color {
        Color.adaptive(
            light: Color.white.opacity(0.42),
            dark: Color.white.opacity(0.20)
        )
    }

    private var chromeMarkFill: Color {
        if opaque {
            return Color.black.opacity(isDark ? 0.35 : 0.12)
        }
        return Color.adaptive(
            light: Color.black.opacity(0.18),
            dark: Color.white.opacity(0.45)
        )
    }

    private var wallpaperColors: [Color] {
        if isDark {
            return [
                Color(red: 0.12, green: 0.14, blue: 0.32),
                Color(red: 0.22, green: 0.12, blue: 0.38),
            ]
        }
        return [
            Color(red: 0.45, green: 0.68, blue: 0.92),
            Color(red: 0.82, green: 0.72, blue: 0.55),
        ]
    }

    var body: some View {
        ZStack {
            // Desktop wallpaper hint — tracks Appearance (Light/Dark/Auto).
            LinearGradient(
                colors: wallpaperColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Panel body — solid for Opaque, frosted wash for Liquid Glass (popover chrome).
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(opaque ? opaqueBodyFill : glassBodyFill)
                .padding(5)

            HStack(alignment: .top, spacing: 3) {
                // Floating sidebar rail
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(opaque ? opaqueElevatedFill : glassElevatedFill)
                    .overlay {
                        if opaque {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .strokeBorder(Color.black.opacity(isDark ? 0.35 : 0.1), lineWidth: 0.5)
                        }
                    }
                    .shadow(color: opaque ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                    .frame(width: 16)
                    .overlay(alignment: .top) {
                        VStack(spacing: 2) {
                            Capsule()
                                .fill(chromeMarkFill)
                                .frame(width: 10, height: 2.5)
                            Capsule()
                                .fill(chromeMarkFill.opacity(0.7))
                                .frame(width: 10, height: 2.5)
                        }
                        .padding(.top, 4)
                    }

                // Section cards column
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(opaque ? opaqueElevatedFill : glassElevatedFill)
                            .overlay {
                                if opaque {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(Color.black.opacity(isDark ? 0.35 : 0.1), lineWidth: 0.5)
                                }
                            }
                            .shadow(color: opaque ? .black.opacity(0.1) : .clear, radius: 0.8, y: 0.4)
                            .frame(height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
        }
    }
}

private enum AppearancePreviewStyle {
    case light
    case dark
}

private struct AppearanceDesktopPreview: View {
    let style: AppearancePreference

    var body: some View {
        switch style {
        case .light:
            desktop(style: .light)
        case .dark:
            desktop(style: .dark)
        case .system:
            HStack(spacing: 0) {
                desktop(style: .light)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                desktop(style: .dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private func desktop(style: AppearancePreviewStyle) -> some View {
        let isDark = style == .dark
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.12, green: 0.14, blue: 0.32), Color(red: 0.22, green: 0.12, blue: 0.38)]
                    : [Color(red: 0.55, green: 0.72, blue: 0.92), Color(red: 0.78, green: 0.88, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Menu bar strip
            Rectangle()
                .fill(isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
                .frame(height: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Apple logo mark
            Image(systemName: "apple.logo")
                .font(.system(size: 5, weight: .medium))
                .foregroundStyle(.white.opacity(isDark ? 0.9 : 0.85))
                .padding(.leading, 4)
                .padding(.top, 1)

            // Window chrome (bottom-leading corner)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 2.5) {
                    Circle().fill(Color(red: 1, green: 0.38, blue: 0.35)).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color(red: 1, green: 0.76, blue: 0.25)).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color(red: 0.35, green: 0.8, blue: 0.4)).frame(width: 3.5, height: 3.5)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(width: 42, height: 22, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isDark ? Color(white: 0.18) : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                )
                .padding(.leading, 6)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
