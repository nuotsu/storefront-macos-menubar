import SwiftUI

struct StoreRailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SafeTriangleController.self) private var safeTriangle
    @FocusState.Binding var searchFocused: Bool

    private var chrome: WidgetChrome {
        WidgetChrome.current(settings: appState.settings)
    }

    private var isFloatingPanel: Bool {
        Theme.isFloatingPanel(settings: appState.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.bottom, 7)

            HStack(spacing: 6) {
                // Count only — `visibleStores` would also sort, which nothing here needs.
                Text("\(appState.stores.lazy.filter(\.isVisible).count) Stores")
                    .font(.panel(11, shopify: chrome.isShopify))
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta36)
                Spacer(minLength: 4)
                if appState.focusArea == .rail {
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.up")
                        Image(systemName: "arrow.down")
                    }
                    .font(.panel(8, weight: .medium, shopify: chrome.isShopify))
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta25)
                    .contentShape(Rectangle())
                    .hoverTooltip("Navigate stores")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))

            Divider().overlay(chrome.isShopify ? Theme.Shopify.hairline : Theme.hairline)

            ScrollView {
                let stores = appState.filteredStores
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stores.enumerated()), id: \.element.id) { index, store in
                        StoreRowView(
                            store: store,
                            shortcutIndex: index + 1,
                            isSelected: store.id == appState.selectedStoreID,
                            isSuppressed: safeTriangle.suppressedRowID == store.id,
                            isShopify: chrome.isShopify
                        ) {
                            appState.toggleFavorite(store)
                        }
                        .equatable()
                    }
                    // Trailing void inside the list — drag only; rows above keep their hits.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            Divider().overlay(chrome.isShopify ? Theme.Shopify.hairline : Theme.hairline)

            navigationLegend
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .frame(width: Theme.railWidth)
        .background {
            ZStack {
                switch chrome {
                case .shopify:
                    Theme.Shopify.surface
                case .macOSOpaque:
                    Theme.panelOpaqueElevatedFill
                case .macOSGlass:
                    SidebarGlassBackground(cornerRadius: Theme.railCornerRadius)
                }
                // Inner chrome padding / gaps: drag only where no control claims the hit.
                if isFloatingPanel {
                    Color.clear
                        .contentShape(Rectangle())
                        .modifier(PanelWindowDragModifier(enabled: true))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.railCornerRadius, style: chrome.cornerStyle))
        .floatingCardChrome(
            chrome: chrome,
            cornerRadius: Theme.railCornerRadius,
            macOSShadowRadius: 4,
            macOSShadowY: 1.5
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.panel(10, shopify: chrome.isShopify))
                .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta30)
                .allowsHitTesting(false)
            // Custom placeholder: AppKit's cell placeholder jumps when the field editor
            // attaches on focus; a SwiftUI label stays put.
            ZStack(alignment: .leading) {
                if appState.query.isEmpty {
                    Text("Search stores")
                        .font(.panel(11.5, shopify: chrome.isShopify))
                        .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta30)
                        .allowsHitTesting(false)
                }
            TextField("", text: Binding(
                get: { appState.query },
                set: { appState.query = $0.replacingOccurrences(of: "\n", with: "") }
            ))
                    .textFieldStyle(.plain)
                    .font(.panel(11.5, shopify: chrome.isShopify))
                    .lineLimit(1)
                    .focused($searchFocused)
                    .focusEffectDisabled()
                    .background(TextFieldAppKitTuning())
                    .onSubmit { }
            }
            KeyComboView(
                combo: appState.settings.focusSearchHotkey,
                font: .panel(8, shopify: chrome.isShopify)
            )
                .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta25)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(chrome.isShopify ? Theme.Shopify.searchFill : Theme.searchFill)
        .clipShape(RoundedRectangle(cornerRadius: chrome.isShopify ? 8 : 6, style: chrome.cornerStyle))
        .overlay {
            if chrome.isShopify {
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .strokeBorder(Theme.Shopify.searchBorder, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    /// Settings link at the bottom of the store rail — Update button sits above when OTA is available.
    private var navigationLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.updateAvailable {
                Button {
                    AppDelegate.shared?.checkForUpdates(nil)
                } label: {
                    Text("Update Available")
                        .font(.panel(10.5, weight: .semibold, shopify: chrome.isShopify))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverTooltip(updatePillHelp)
                .padding(.top, 6)
            }

            LegendLinkRow(systemImage: "gearshape", label: "Settings", help: "Settings", shortcutKey: ",") {
                appState.selectedSettingsTab = .general
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            }
            .padding(.top, 4)
        }
    }

    private var updatePillHelp: String {
        if let version = appState.pendingUpdateVersion, !version.isEmpty {
            let labeled = version.hasPrefix("v") ? version : "v\(version)"
            return "Update to \(labeled) is ready. Click to install and restart."
        }
        return "An update is ready. Click to install and restart."
    }
}

/// Compact rail footer link — same hover fill language as store rows, but smaller so it
/// stays visually secondary to the sidebar list above.
private struct LegendLinkRow: View {
    let systemImage: String
    let label: String
    let help: String
    var shortcutKey: String? = nil
    let action: () -> Void
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var isShopify: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    private var contentColor: Color {
        if isShopify {
            return isHovering ? Theme.Shopify.textPrimary : Theme.Shopify.textSecondary
        }
        return isHovering ? Theme.textBody : Theme.textMeta36
    }

    private var iconColor: Color {
        if isShopify {
            return isHovering ? Theme.Shopify.textPrimary : Theme.Shopify.textMeta
        }
        return isHovering ? Theme.textBody : Theme.textMeta30
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.panel(9.5, weight: .medium, shopify: isShopify))
                    .foregroundStyle(iconColor)
                    .frame(width: 10, alignment: .center)
                Text(label)
                    .font(.panel(10.5, shopify: isShopify))
                    .foregroundStyle(contentColor)
                Spacer(minLength: 4)
                if let shortcutKey {
                    HStack(spacing: 1) {
                        Image(systemName: "command")
                            .font(.panel(8, weight: .medium, shopify: isShopify))
                        Text(shortcutKey)
                            .font(isShopify ? .inter(9) : .mono(9))
                    }
                    .foregroundStyle(
                        isShopify
                            ? Theme.Shopify.textMeta
                            : (isHovering ? Theme.textMeta36 : Theme.textMeta25)
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? (isShopify ? Theme.Shopify.hoverFill : Theme.hoverFill) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: isShopify ? .circular : .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

private struct StoreRowView: View, Equatable {
    let store: Store
    let shortcutIndex: Int
    let isSelected: Bool
    let isSuppressed: Bool
    let isShopify: Bool
    let onToggleFavorite: () -> Void
    @State private var isHovering = false
    /// Row frame in tooltip space — stars and ←→ share this for a common tooltip Y.
    @State private var tooltipRowFrame: CGRect = .zero

    static func == (lhs: StoreRowView, rhs: StoreRowView) -> Bool {
        lhs.store == rhs.store
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isSuppressed == rhs.isSuppressed
            && lhs.isShopify == rhs.isShopify
    }

    /// Hover state used for visual affordances only — false while the safe triangle is
    /// suppressing this row, so it shows no highlight at all mid-transit.
    private var effectiveHovering: Bool { isHovering && !isSuppressed }

    private var showStar: Bool { store.isFavorite || effectiveHovering || isSelected }
    /// Selected rows always show ←→; others keep `⌘N` through 9.
    private var hasBadge: Bool { isSelected || shortcutIndex <= 9 }

    private static let starWidth: CGFloat = 16
    private static let badgeGap: CGFloat = 2
    private static let edgeGap: CGFloat = 0
    private static let badgeWidth: CGFloat = 18
    /// Nudges ←→ into the row's trailing padding without moving the star.
    private static let selectedBadgeNudge: CGFloat = 3

    /// Distance from the row's trailing edge to the star's own right edge — flush
    /// near the edge when there's no badge, or just past the badge when there is.
    /// Always uses the `⌘N` slot metrics so selecting a store never shifts the star.
    private var starTrailingOffset: CGFloat {
        hasBadge ? Self.badgeWidth + Self.badgeGap : Self.edgeGap
    }

    /// Always reserve star room so hover/select opacity alone never reflows the name
    /// (and never re-emits row-frame preferences from a layout shift).
    private var nameTrailingReserve: CGFloat {
        hasBadge ? 4 : Self.starWidth + Self.edgeGap
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                StoreFaviconView(store: store, size: 16)
                Text(store.displayName)
                    .font(.panel(12.5, shopify: isShopify))
                    .foregroundStyle(
                        isShopify
                            ? Theme.Shopify.textPrimary
                            : (isSelected ? Theme.textPrimary : Theme.textBody)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, nameTrailingReserve)
                Spacer(minLength: 4)
                shortcutBadge
                    .offset(x: isSelected ? Self.selectedBadgeNudge : 0)
            }

            FavoriteButton(
                isFavorite: store.isFavorite,
                isRowHovering: effectiveHovering,
                isShopify: isShopify,
                verticalBand: tooltipRowFrame,
                action: onToggleFavorite
            )
                .padding(.trailing, starTrailingOffset)
                .opacity(showStar ? 1 : 0)
                // Keep the star hittable only while visible — opacity alone still receives taps.
                .allowsHitTesting(showStar)
        }
        .padding(.leading, 15)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        // Accent sits above the selection/hover fill so an opaque selected
        // background can't cover it (stacked `.background` draws behind the prior one).
        // Clip only the backdrop so favorite tooltips aren't cut off.
        .background {
            ZStack(alignment: .leading) {
                rowBackground
                RoundedRectangle(cornerRadius: 2)
                    .fill(store.color)
                    .frame(width: 3)
                    .padding(.leading, 5)
                    .padding(.vertical, 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: isShopify ? .circular : .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: isShopify ? .circular : .continuous))
        .background(
            GeometryReader { geo in
                let panelFrame = geo.frame(in: .named("panel"))
                let tooltipFrame = geo.frame(in: .named(HoverTooltipController.coordinateSpaceName))
                Color.clear
                    .preference(key: RowFramePreferenceKey.self, value: [store.id: panelFrame])
                    .onAppear { tooltipRowFrame = tooltipFrame }
                    .onChange(of: tooltipFrame) { _, frame in
                        tooltipRowFrame = frame
                    }
            }
        )
        .onHover { hovering in
            // Selection itself is driven centrally by SafeTriangleController, sourced
            // from one continuous mouse-tracking stream — this is only for this row's
            // own local visual state (its hover fill, the star's fade-in).
            isHovering = hovering
        }
    }

    /// Selected: static ←→. Unselected (1–9): `⌘N`. Collapses past 9 when not selected.
    private var shortcutBadge: some View {
        Group {
            if isSelected {
                HStack(spacing: 0) {
                    Image(systemName: "arrow.left")
                    Image(systemName: "arrow.right")
                }
                .font(.panel(8, weight: .medium, shopify: isShopify))
                .contentShape(Rectangle())
                .hoverTooltip(
                    "Navigate cards",
                    verticalBand: tooltipRowFrame == .zero ? nil : tooltipRowFrame
                )
            } else if shortcutIndex <= 9 {
                HStack(spacing: 1) {
                    Image(systemName: "command")
                        .font(.panel(8, weight: .medium, shopify: isShopify))
                    Text("\(shortcutIndex)")
                        .font(isShopify ? .inter(9) : .mono(9))
                }
            }
        }
        .frame(width: hasBadge ? Self.badgeWidth : 0, alignment: .trailing)
        .foregroundStyle(isShopify ? Theme.Shopify.textMeta : Theme.textMeta25)
    }

    private var rowBackground: Color {
        if isShopify {
            if isSelected || effectiveHovering { return Theme.Shopify.hoverFill }
            return .clear
        }
        if isSelected { return Theme.controlFill }
        if effectiveHovering { return Theme.hoverFill }
        return .clear
    }
}

/// Favorite toggle drawn as a fixed-position overlay (see `StoreRowView`) rather than
/// an `HStack` participant, so its own fade-in/out never nudges any sibling.
private struct FavoriteButton: View {
    let isFavorite: Bool
    let isRowHovering: Bool
    var isShopify: Bool = false
    var verticalBand: CGRect = .zero
    let action: () -> Void

    var body: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .font(.panel(10, shopify: isShopify))
            .foregroundStyle(
                isShopify
                    ? (isFavorite ? Theme.Shopify.textPrimary : Theme.Shopify.textMeta)
                    : (isFavorite ? Theme.textPrimary : Theme.textMeta30)
            )
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .hoverTooltip(
                "Toggle favorite",
                verticalBand: verticalBand == .zero ? nil : verticalBand
            )
            .onTapGesture(perform: action)
    }
}
