import SwiftUI

struct StoreRailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SafeTriangleController.self) private var safeTriangle
    @FocusState.Binding var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: WidgetChrome {
        WidgetChrome.current(settings: appState.settings)
    }

    @Environment(\.isFloatingPanel) private var isFloatingPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.bottom, 7)

            HStack(spacing: 6) {
                // Count only — `visibleStores` would also sort, which nothing here needs.
                Text("\(appState.stores.lazy.filter(\.isVisible).count) stores")
                    .font(.panel(11, shopify: chrome.isShopify))
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.Sidebar.textMeta : Theme.textMeta36)
                Spacer(minLength: 4)
                if appState.focusArea == .rail {
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.up")
                        Image(systemName: "arrow.down")
                    }
                    .font(.panel(8, weight: .medium, shopify: chrome.isShopify))
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.Sidebar.textMeta : Theme.textMeta25)
                    .contentShape(Rectangle())
                    .hoverTooltip("Navigate stores")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))

            Divider().overlay(chrome.isShopify ? Theme.Shopify.Sidebar.hairline : Theme.hairline)

            ScrollView {
                let stores = appState.filteredStores
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stores.enumerated()), id: \.element.id) { index, store in
                        StoreRowView(
                            store: store,
                            shortcutIndex: index + 1,
                            isSelected: store.id == appState.selectedStoreID,
                            isSuppressed: safeTriangle.suppressedRowID == store.id,
                            isShopify: chrome.isShopify,
                            canMoveUp: appState.canMoveStore(store, offset: -1),
                            canMoveDown: appState.canMoveStore(store, offset: 1)
                        ) { action in
                            switch action {
                            case .togglePin: appState.togglePinned(store)
                            case .moveUp: appState.moveStore(store, offset: -1)
                            case .moveDown: appState.moveStore(store, offset: 1)
                            case .hide: appState.setStoreVisible(store, false)
                            }
                        }
                        .equatable()
                    }
                    let hidden = appState.hiddenStores.filter { $0.matchesSearchQuery(appState.query) }
                    if !hidden.isEmpty {
                        HiddenStoresSection(stores: hidden, isShopify: chrome.isShopify)
                            .padding(.top, stores.isEmpty ? 0 : 6)
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

            Divider().overlay(chrome.isShopify ? Theme.Shopify.Sidebar.hairline : Theme.hairline)

            navigationLegend
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 7)
        .frame(width: Theme.railWidth)
        .background {
            ZStack {
                switch chrome {
                case .shopify:
                    Theme.Shopify.Sidebar.fill
                case .macOSOpaque:
                    Theme.panelOpaqueElevatedFill
                case .macOSGlass:
                    SidebarGlassBackground()
                }
                // Inner chrome padding / gaps: drag only where no control claims the hit.
                if isFloatingPanel {
                    Color.clear
                        .contentShape(Rectangle())
                        .modifier(PanelWindowDragModifier(enabled: true))
                }
            }
        }
        // Dark Shopify nav inside a light-locked widget: resolves the text field, caret,
        // and adaptive favicon plates for a dark surface.
        .environment(\.colorScheme, chrome.isShopify ? .dark : colorScheme)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image("SearchIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(chrome.isShopify ? Theme.Shopify.Sidebar.searchText : Theme.textMeta30)
                .allowsHitTesting(false)
            // Custom placeholder: AppKit's cell placeholder jumps when the field editor
            // attaches on focus; a SwiftUI label stays put.
            ZStack(alignment: .leading) {
                if appState.query.isEmpty {
                    Text("Search stores")
                        .font(.panel(11.5, shopify: chrome.isShopify))
                        .foregroundStyle(chrome.isShopify ? Theme.Shopify.Sidebar.searchText : Theme.textMeta30)
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
                    .background(TextFieldAppKitTuning(caretColor: chrome.isShopify ? .white : nil))
                    .onSubmit { }
            }
            KeyComboView(
                combo: appState.settings.focusSearchHotkey,
                font: .panel(8, shopify: chrome.isShopify)
            )
                .foregroundStyle(chrome.isShopify ? Theme.Shopify.Sidebar.searchText : Theme.textMeta25)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(chrome.isShopify ? Theme.Shopify.Sidebar.hairline : Theme.hairline, lineWidth: 0.5)
                }
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background {
            if chrome.isShopify {
                ShopifySidebarRaisedSurface(fill: Theme.Shopify.Sidebar.searchFill, cornerRadius: 9)
            } else {
                RoundedRectangle(cornerRadius: 6, style: chrome.cornerStyle)
                    .fill(Theme.searchFill)
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

            LegendLinkRow(iconName: "SettingsIcon", label: "Settings", help: "Settings", shortcutKey: ",") {
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
    let iconName: String
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
            return isHovering ? Theme.Shopify.Sidebar.textPrimary : Theme.Shopify.Sidebar.textSecondary
        }
        return isHovering ? Theme.textBody : Theme.textMeta36
    }

    private var iconColor: Color {
        if isShopify {
            return isHovering ? Theme.Shopify.Sidebar.textPrimary : Theme.Shopify.Sidebar.textMeta
        }
        return isHovering ? Theme.textBody : Theme.textMeta30
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(iconColor)
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
                            ? Theme.Shopify.Sidebar.textMeta
                            : (isHovering ? Theme.textMeta36 : Theme.textMeta25)
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? (isShopify ? Theme.Shopify.Sidebar.hoverFill : Theme.hoverFill) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: isShopify ? .circular : .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

private enum StoreRowAction {
    case togglePin, moveUp, moveDown, hide
}

private struct StoreRowView: View, Equatable {
    let store: Store
    let shortcutIndex: Int
    let isSelected: Bool
    let isSuppressed: Bool
    let isShopify: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onAction: (StoreRowAction) -> Void
    @State private var isHovering = false
    /// Row frame in tooltip space — pins and ←→ share this for a common tooltip Y.
    @State private var tooltipRowFrame: CGRect = .zero

    static func == (lhs: StoreRowView, rhs: StoreRowView) -> Bool {
        lhs.store == rhs.store
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isSuppressed == rhs.isSuppressed
            && lhs.isShopify == rhs.isShopify
            && lhs.canMoveUp == rhs.canMoveUp
            && lhs.canMoveDown == rhs.canMoveDown
    }

    /// Hover state used for visual affordances only — false while the safe triangle is
    /// suppressing this row, so it shows no highlight at all mid-transit.
    private var effectiveHovering: Bool { isHovering && !isSuppressed }

    private var showPin: Bool { store.isPinned || effectiveHovering || isSelected }
    /// Selected rows always show ←→; others keep `⌘N` through 9.
    private var hasBadge: Bool { isSelected || shortcutIndex <= 9 }

    private static let pinWidth: CGFloat = 16
    private static let badgeGap: CGFloat = 2
    private static let badgeWidth: CGFloat = 18
    /// Nudges ←→ into the row's trailing padding without moving the pin.
    private static let selectedBadgeNudge: CGFloat = 3
    /// Length of the name's fade-out ahead of the trailing controls (or the row edge).
    private static let fadeWidth: CGFloat = 18

    /// Width the trailing controls cover at the name's right edge. The name runs the full
    /// row width underneath them and fades out just before this inset.
    private var controlsInset: CGFloat {
        (hasBadge ? Self.badgeWidth + Self.badgeGap : 0) + (showPin ? Self.pinWidth : 0)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                StoreFaviconView(store: store, size: 16)
                nameLabel
            }

            HStack(spacing: 0) {
                PinButton(
                    isPinned: store.isPinned,
                    isShopify: isShopify,
                    verticalBand: tooltipRowFrame,
                    action: { onAction(.togglePin) }
                )
                    .opacity(showPin ? 1 : 0)
                    // Keep the pin hittable only while visible — opacity alone still receives taps.
                    .allowsHitTesting(showPin)
                if hasBadge {
                    shortcutBadge
                        .offset(x: isSelected ? Self.selectedBadgeNudge : 0)
                        .padding(.leading, Self.badgeGap)
                }
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        // Accent sits above the selection/hover fill so an opaque selected
        // background can't cover it (stacked `.background` draws behind the prior one).
        // Clip only the backdrop so pin tooltips aren't cut off.
        .background {
            ZStack(alignment: .leading) {
                if isShopify && isSelected {
                    ShopifySidebarRaisedSurface(fill: Theme.Shopify.Sidebar.selectedFill, cornerRadius: 7)
                }
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
            // own local visual state (its hover fill, the pin's fade-in).
            isHovering = hovering
        }
        .contextMenu {
            Button {
                onAction(.togglePin)
            } label: {
                Label(store.isPinned ? "Unpin" : "Pin", systemImage: store.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button {
                onAction(.moveUp)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(!canMoveUp)
            Button {
                onAction(.moveDown)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(!canMoveDown)
            Divider()
            Button {
                onAction(.hide)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
        }
    }

    /// Never truncated: the name runs under the trailing controls and fades out ahead of
    /// them, so hovering (which reveals the pin) only shifts the fade, not the text.
    private var nameLabel: some View {
        Text(store.displayName)
            .font(.panel(12.5, shopify: isShopify))
            .foregroundStyle(
                isShopify
                    ? (isSelected ? Theme.Shopify.Sidebar.textPrimary : Theme.Shopify.Sidebar.textItem)
                    : (isSelected ? Theme.textPrimary : Theme.textBody)
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(TrailingFadeMask(fadeWidth: Self.fadeWidth, trailingInset: controlsInset))
            .animation(.easeOut(duration: 0.12), value: controlsInset)
    }

    /// Selected: static ←→. Unselected (1–9): `⌘N`.
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
            } else {
                HStack(spacing: 1) {
                    Image(systemName: "command")
                        .font(.panel(8, weight: .medium, shopify: isShopify))
                    Text("\(shortcutIndex)")
                        .font(isShopify ? .inter(9) : .mono(9))
                }
            }
        }
        .frame(width: Self.badgeWidth, alignment: .trailing)
        .foregroundStyle(isShopify ? Theme.Shopify.Sidebar.textMeta : Theme.textMeta25)
    }

    private var rowBackground: Color {
        if isShopify {
            if isSelected { return .clear }
            if effectiveHovering { return Theme.Shopify.Sidebar.hoverFill }
            return .clear
        }
        if isSelected { return Theme.controlFill }
        if effectiveHovering { return Theme.hoverFill }
        return .clear
    }
}

/// Opaque up to `fadeWidth + trailingInset` from the trailing edge, then a linear fade,
/// then fully clear under the trailing controls. A mask (rather than a gradient painted
/// in the row's fill) works over every backdrop: glass, opaque, hover, and selected.
private struct TrailingFadeMask: View {
    let fadeWidth: CGFloat
    let trailingInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Color.clear
                .frame(width: trailingInset)
        }
    }
}

/// Pin toggle drawn in the row's trailing overlay (see `StoreRowView`), on top of the
/// name's fade rather than beside it, so its fade-in/out never reflows the name.
private struct PinButton: View {
    let isPinned: Bool
    var isShopify: Bool = false
    var verticalBand: CGRect = .zero
    let action: () -> Void

    var body: some View {
        Image(isPinned ? "PinFilledIcon" : "PinIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundStyle(
                isShopify
                    ? (isPinned ? Theme.Shopify.Sidebar.textPrimary : Theme.Shopify.Sidebar.textMeta)
                    : (isPinned ? Theme.textPrimary : Theme.textMeta30)
            )
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .hoverTooltip(
                isPinned ? "Unpin" : "Pin",
                verticalBand: verticalBand == .zero ? nil : verticalBand
            )
            .onTapGesture(perform: action)
    }
}

/// Subdued disclosure under the active list: hidden stores stay one click away without
/// joining hover-select, keyboard navigation, or the `⌘N` shortcuts.
private struct HiddenStoresSection: View {
    let stores: [Store]
    let isShopify: Bool
    @Environment(AppState.self) private var appState
    @AppStorage("rail.hiddenStoresExpanded") private var isExpanded = false
    @State private var isHeaderHovering = false

    private var metaColor: Color {
        isShopify ? Theme.Shopify.Sidebar.textMeta : Theme.textMeta36
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image("ChevronRightIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Hidden stores")
                    Text("\(stores.count)")
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .font(.panel(10.5, shopify: isShopify))
                .foregroundStyle(metaColor)
                .opacity(isHeaderHovering ? 1 : 0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovering = $0 }

            if isExpanded {
                ForEach(stores) { store in
                    HiddenStoreRow(store: store, isShopify: isShopify) {
                        appState.setStoreVisible(store, true)
                    }
                }
            }
        }
    }
}

private struct HiddenStoreRow: View {
    let store: Store
    let isShopify: Bool
    let onUnhide: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                StoreFaviconView(store: store, size: 14)
                    .saturation(0)
                Text(store.displayName)
                    .font(.panel(11.5, shopify: isShopify))
                    .foregroundStyle(isShopify ? Theme.Shopify.Sidebar.textSecondary : Theme.textMeta36)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask(TrailingFadeMask(fadeWidth: 18, trailingInset: isHovering ? 16 : 0))
            }
            .opacity(isHovering ? 0.9 : 0.6)

            Image(systemName: "eye")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isShopify ? Theme.Shopify.Sidebar.textPrimary : Theme.textBody)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .hoverTooltip("Unhide")
                .onTapGesture(perform: onUnhide)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .padding(.leading, 16)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(
            (isHovering ? (isShopify ? Theme.Shopify.Sidebar.hoverFill : Theme.hoverFill) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: isShopify ? .circular : .continuous))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: onUnhide) {
                Label("Unhide", systemImage: "eye")
            }
        }
    }
}
