import SwiftUI
import AppKit

/// Opens a link. A normal click closes the panel; ⌘-click keeps it open while the
/// browser activates (transient popovers don't always dismiss on URL open alone).
/// Pass `keepOpen` explicitly for keyboard shortcuts that include ⌘ so they don't
/// accidentally inherit the click keep-open path.
@MainActor
func openStoreLink(_ url: URL, keepOpen: Bool? = nil) {
    let shouldKeepOpen = keepOpen ?? NSEvent.modifierFlags.contains(.command)
    if shouldKeepOpen {
        AppDelegate.shared?.keepPopoverOpenTemporarily()
    }
    NSWorkspace.shared.open(url)
    if !shouldKeepOpen {
        AppDelegate.shared?.closePanel()
    }
}

struct StoreDetailView: View {
    @Environment(AppState.self) private var appState
    let store: Store
    var focusedRowSearchID: FocusState<String?>.Binding
    /// Invoked when ⌃S is pressed while a row search field holds focus (TextField can
    /// swallow the chord before `PanelView.onKeyPress` sees it).
    var onToggleLinkSearchKey: () -> Bool = { false }
    @Environment(\.colorScheme) private var colorScheme

    var enabledSections: [SectionID] { appState.enabledSections }

    /// A section paired with its index in `enabledSections`, so the card grid never has
    /// to scan back for it. `AppState.enabledSections` allocates a fresh filtered array
    /// on every access, so the whole grid is derived from one read per body.
    private struct SectionSlot: Identifiable, Hashable {
        let index: Int
        let section: SectionID
        var id: SectionID { section }
    }

    /// Slots chunked into pairs so each row can be a `GridRow` — `Grid` (unlike
    /// `LazyVGrid`) equalizes height across a row instead of letting each column
    /// stack independently, which is what kept the two columns from lining up.
    private struct SectionGridRow: Identifiable {
        let id: Int
        let slots: [SectionSlot]
    }

    private func sectionRows(for sections: [SectionID]) -> [SectionGridRow] {
        stride(from: 0, to: sections.count, by: 2).enumerated().map { rowIndex, start in
            SectionGridRow(
                id: rowIndex,
                slots: (start..<min(start + 2, sections.count)).map {
                    SectionSlot(index: $0, section: sections[$0])
                }
            )
        }
    }

    var body: some View {
        let sections = enabledSections
        let focusedSectionIndex = appState.focusArea == .cards ? appState.focusedSectionIndex : -1
        let chrome = WidgetChrome.current(settings: appState.settings)

        // macOS: soft progressive blur under a top bar (`safeAreaBar` + scroll edge).
        // Shopify: solid Polaris-style header band — no blur/transparency.
        ScrollViewReader { scrollProxy in
            ScrollView {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(sectionRows(for: sections)) { row in
                        GridRow {
                            ForEach(row.slots) { slot in
                                let isFocused = slot.index == focusedSectionIndex
                                SectionCardView(
                                    section: slot.section,
                                    store: store,
                                    isFocused: isFocused,
                                    // Only the focused card cares about the row index —
                                    // pinning the rest to -1 keeps an arrow-key row move
                                    // from changing a parameter on every other card.
                                    focusedRowIndex: isFocused ? appState.focusedRowIndex : -1,
                                    focusedRowSearchID: focusedRowSearchID,
                                    onToggleLinkSearchKey: onToggleLinkSearchKey
                                )
                                .id(slot.section)
                            }
                            if row.slots.count == 1 {
                                Color.clear
                            }
                        }
                    }
                }
                .padding(12)
                // Gaps / padding around cards: drag. Cards sit above and keep their hits.
                // (Background is sized to the grid — never use maxHeight: .infinity here.)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))
                }
            }
            .modifier(StoreDetailScrollHeaderModifier(chrome: chrome) {
                header(chrome: chrome)
            })
            // Scroll only when keyboard navigation bumps `cardScrollGeneration` — not when
            // hover/click updates `focusedSectionIndex`.
            .onChange(of: appState.cardScrollGeneration) { _, _ in
                scrollToFocusedSection(proxy: scrollProxy, index: appState.focusedSectionIndex)
            }
        }
    }

    /// Keeps the keyboard-focused card on screen while looping Left/Right through the grid.
    private func scrollToFocusedSection(proxy: ScrollViewProxy, index: Int) {
        guard index < enabledSections.count else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(enabledSections[index], anchor: .center)
        }
    }

    private var isFloatingPanel: Bool {
        Theme.isFloatingPanel(settings: appState.settings)
    }

    private func header(chrome: WidgetChrome) -> some View {
        let isShopify = chrome.isShopify
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StoreFaviconView(store: store, size: 22)
                Text(store.displayName)
                    .font(.panel(16, weight: .semibold, shopify: isShopify))
                    .foregroundStyle(isShopify ? Theme.Shopify.textPrimary : Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HeaderRowDragBackground(enabled: isFloatingPanel))

            CopyableHandleView(handle: store.handle, domain: store.myshopifyDomain, accentColor: store.color)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(HeaderRowDragBackground(enabled: isFloatingPanel))

            HStack(spacing: 6) {
                if let adminURL = store.adminURL {
                    HeaderActionButton(
                        title: "Admin",
                        iconName: "HomeIcon",
                        background: store.color,
                        foreground: store.accentTextColor,
                        shortcutLetter: appState.settings.openAdminHotkey.mnemonicLetter
                    ) {
                        openStoreLink(adminURL)
                    }
                }
                if let shopURL = store.shopURL {
                    HeaderActionButton(
                        title: "Online Store",
                        iconName: "StoreIcon",
                        background: store.color.pillBackground(colorScheme: colorScheme),
                        foreground: store.color.pillTextColor(colorScheme: colorScheme),
                        shortcutLetter: appState.settings.openOnlineStoreHotkey.mnemonicLetter
                    ) {
                        openStoreLink(shopURL)
                    }
                }
                if let supportURL = store.supportURL {
                    HeaderActionButton(
                        title: "Support",
                        iconName: "QuestionCircleIcon",
                        background: store.color.pillBackground(colorScheme: colorScheme),
                        foreground: store.color.pillTextColor(colorScheme: colorScheme),
                        shortcutLetter: appState.settings.openSupportHotkey.mnemonicLetter
                    ) {
                        openStoreLink(supportURL)
                    }
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HeaderRowDragBackground(enabled: isFloatingPanel))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque page fill must own the drag gesture — a clear layer behind it never
        // receives void hits. Background is layout-neutral (unlike Color.clear children).
        .background {
            Group {
                if isShopify {
                    Theme.Shopify.pageBackground
                } else {
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))
        }
        .overlay(alignment: .bottom) {
            if isShopify {
                Rectangle()
                    .fill(Theme.Shopify.hairline)
                    .frame(height: 1)
            }
        }
    }
}

/// Drag handle behind a header row so trailing void moves the window without layout flex.
private struct HeaderRowDragBackground: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .contentShape(Rectangle())
                .modifier(PanelWindowDragModifier(enabled: enabled))
        }
    }
}

/// Pins the store header above the section grid.
/// Shopify uses a solid inset (no progressive blur); macOS keeps the soft scroll-edge recipe.
private struct StoreDetailScrollHeaderModifier<Header: View>: ViewModifier {
    let chrome: WidgetChrome
    @ViewBuilder let header: () -> Header

    @ViewBuilder
    func body(content: Content) -> some View {
        if chrome.isShopify {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    header()
                }
        } else {
            content
                .settingsTopScrollEdgeBlur()
                .detailHeaderSafeAreaBar {
                    header()
                }
        }
    }
}

/// The store's `myshopify.com` domain, shown next to its display name as two
/// tappable segments. Click the handle to copy just that id; click `.myshopify.com`
/// to copy the full domain. A checkmark fades in beside it to confirm.
private struct CopyableHandleView: View {
    let handle: String
    let domain: String
    let accentColor: Color
    @Environment(AppState.self) private var appState
    @State private var hoveringHandle = false
    @State private var hoveringSuffix = false
    @State private var didCopy = false
    @State private var hideCheckmarkTask: Task<Void, Never>?

    private static let suffix = ".myshopify.com"

    private var isShopify: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    private var handleColor: Color {
        if isShopify {
            return (hoveringHandle || hoveringSuffix) ? Theme.Shopify.textPrimary : Theme.Shopify.textSecondary
        }
        return (hoveringHandle || hoveringSuffix) ? Theme.textBody : Theme.textSecondary
    }

    private var suffixColor: Color {
        if isShopify {
            return hoveringSuffix ? Theme.Shopify.textPrimary : Theme.Shopify.textMeta
        }
        return hoveringSuffix ? Theme.textBody : Theme.textMeta30
    }

    private var handleFont: Font {
        .mono(10.5)
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(handle)
                    .font(handleFont)
                    .foregroundStyle(handleColor)
                    .overlay(alignment: .bottom) {
                        TightDashUnderline(color: handleColor)
                            .opacity(hoveringHandle || hoveringSuffix ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hoveringHandle = $0 }
                    .onTapGesture { copy(handle) }
                    .hoverTooltip("Copy store handle")

                Text(Self.suffix)
                    .font(handleFont)
                    .foregroundStyle(suffixColor)
                    .overlay(alignment: .bottom) {
                        TightDashUnderline(color: suffixColor)
                            .opacity(hoveringSuffix ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hoveringSuffix = $0 }
                    .onTapGesture { copy(domain) }
                    .hoverTooltip("Copy store domain")
            }
            Image(systemName: "checkmark")
                .font(.panel(9, weight: .bold, shopify: isShopify))
                .foregroundStyle(accentColor)
                .opacity(didCopy ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: didCopy)
        .animation(.easeOut(duration: 0.12), value: hoveringHandle)
        .animation(.easeOut(duration: 0.12), value: hoveringSuffix)
        // Detail keeps identity across store switches — clear ephemeral copy UI.
        .onChange(of: domain) { _, _ in
            hideCheckmarkTask?.cancel()
            hideCheckmarkTask = nil
            didCopy = false
            hoveringHandle = false
            hoveringSuffix = false
        }
        .onDisappear {
            hideCheckmarkTask?.cancel()
            hideCheckmarkTask = nil
        }
    }

    private func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        didCopy = true
        // Only the latest click owns the fade-out — older sleeps must not clear a newer copy.
        hideCheckmarkTask?.cancel()
        hideCheckmarkTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
            hideCheckmarkTask = nil
        }
    }
}

/// Compact dashed underline — tighter than system `.dash` spacing.
private struct TightDashUnderline: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2.5, 1.5]))
        }
        .frame(height: 1)
        .offset(y: 1)
        .allowsHitTesting(false)
    }
}

/// Compact dotted underline — round dots, not dashes.
private struct TightDotUnderline: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            // Inset so round caps sit inside the letter’s advance, not past its edges.
            let inset: CGFloat = 0.75
            let width = max(0, geo.size.width - inset * 2)
            Path { path in
                path.move(to: CGPoint(x: inset, y: 0.5))
                path.addLine(to: CGPoint(x: inset + width, y: 0.5))
            }
            // Near-zero dash + round caps → true dots rather than short dashes.
            .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [0.01, 2.25]))
        }
        .frame(height: 1)
        // Sit just under the glyph (overlay `.bottom` already clears the baseline box).
        .offset(y: -1)
        .allowsHitTesting(false)
    }
}

/// A plain, chrome-free tappable pill. Avoids `Button`/`Link`'s system hover/press
/// styling, which on recent macOS versions can subtly resize the control on hover.
private struct HeaderActionButton: View {
    let title: String
    let iconName: String
    let background: Color
    let foreground: Color
    /// When set to a letter that appears in `title`, that first match gets a dotted
    /// underline as a mnemonic for the panel shortcut.
    var shortcutLetter: Character? = nil
    let action: () -> Void
    @Environment(AppState.self) private var appState

    private var isShopify: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isShopify ? 8 : 6, style: isShopify ? .circular : .continuous)
    }

    /// macOS: lighter at the top. Shopify/Polaris: inverted — darker top, lighter bottom.
    private var fill: LinearGradient {
        if isShopify {
            return LinearGradient(
                colors: [
                    Color.black.composited(over: background, alpha: 0.06),
                    Color.white.composited(over: background, alpha: 0.05),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white.composited(over: background, alpha: 0.12),
                background,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Splits `title` around the first case-insensitive match of `shortcutLetter`.
    private var mnemonicParts: (before: String, letter: String, after: String)? {
        guard let shortcutLetter,
              let index = title.firstIndex(where: { $0.lowercased() == String(shortcutLetter).lowercased() })
        else { return nil }
        return (
            String(title[..<index]),
            String(title[index]),
            String(title[title.index(after: index)...])
        )
    }

    @ViewBuilder
    private var titledText: some View {
        if let parts = mnemonicParts {
            HStack(spacing: 0) {
                Text(parts.before)
                Text(parts.letter)
                    .overlay(alignment: .bottom) {
                        TightDotUnderline(color: foreground)
                    }
                Text(parts.after)
            }
        } else {
            Text(title)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            titledText
                .font(.panel(11, weight: .medium, shopify: isShopify))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background { buttonChrome }
        .contentShape(shape)
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private var buttonChrome: some View {
        if isShopify {
            // Polaris primary-style: inverted fill + outer border + soft lift shadow.
            shape
                .fill(fill)
                .overlay {
                    shape.strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
        } else {
            shape
                .fill(fill)
                .shadow(color: .black.opacity(0.14), radius: 1, y: 0.5)
                .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
    }
}

/// One section's card in the right-column grid — a title label plus its compact link list.
struct SectionCardView: View {
    let section: SectionID
    let store: Store
    var isFocused: Bool = false
    var focusedRowIndex: Int = 0
    var focusedRowSearchID: FocusState<String?>.Binding
    var onToggleLinkSearchKey: () -> Bool = { false }
    @Environment(AppState.self) private var appState

    private var rows: [LinkRow] { StaticLinkCatalog.rows(for: section) }
    private var chrome: WidgetChrome { WidgetChrome.current(settings: appState.settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(chrome.isShopify ? section.title : section.title.uppercased())
                    .font(
                        chrome.isShopify
                            ? .inter(12, weight: .semibold)
                            : .mono(9.5, weight: .semibold)
                    )
                    .tracking(chrome.isShopify ? 0 : 1.2)
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.textSecondary : Theme.textMeta40)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isFocused {
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.up")
                        Image(systemName: "arrow.down")
                    }
                    .font(.panel(8, weight: .medium, shopify: chrome.isShopify))
                    .foregroundStyle(chrome.isShopify ? Theme.Shopify.textMeta : Theme.textMeta25)
                    .contentShape(Rectangle())
                    .hoverTooltip("Cycle through links. Enter to open.")
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    CardLinkRow(
                        row: row,
                        store: store,
                        section: section,
                        rowIndex: index,
                        isActive: isFocused && index == focusedRowIndex,
                        focusedRowSearchID: focusedRowSearchID,
                        onToggleLinkSearchKey: onToggleLinkSearchKey
                    )
                }
            }
            // Grid equalizes card height across a GridRow's two columns (see the comment
            // on `sectionRows`) — a short card (e.g. one row) gets offered extra vertical
            // space to match its taller neighbor. Without `fixedSize`, that extra space
            // was stretching the last row itself rather than landing as blank card padding
            // below it (the intended, already-accepted tradeoff of using `Grid` here).
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Clip only the backdrop so row hover shadows aren't cut off.
        .background {
            Group {
                switch chrome {
                case .shopify:
                    Theme.Shopify.surface
                case .macOSOpaque:
                    Theme.panelOpaqueElevatedFill
                case .macOSGlass:
                    SidebarGlassBackground(cornerRadius: 9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: chrome.cornerStyle))
        }
        .floatingCardChrome(
            chrome: chrome,
            cornerRadius: 9,
            macOSShadowRadius: 3,
            macOSShadowY: 1
        )
    }
}

/// A single static link within a section card. Fixed padding at all times — only the
/// background fill toggles on hover — so hovering never shifts the row's size
/// or its neighbors' positions.
private struct CardLinkRow: View {
    let row: LinkRow
    let store: Store
    let section: SectionID
    let rowIndex: Int
    /// Sole active highlight for this store's card grid — driven by `AppState` so hover,
    /// click, and arrow keys share one selection (hover/click override arrows).
    var isActive: Bool = false
    var focusedRowSearchID: FocusState<String?>.Binding
    var onToggleLinkSearchKey: () -> Bool = { false }
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    /// True while the pointer is inside this row — used to activate after hover is
    /// re-armed following a keyboard scroll (`.onHover` does not re-fire for a
    /// stationary cursor).
    @State private var pointerInside = false

    /// Lives in `AppState` (not local `@State`) so the ⌃S keyboard shortcut can toggle a
    /// row's search regardless of which `CardLinkRow` instance it belongs to, and so
    /// switching stores and back doesn't lose it (detail keeps identity across stores).
    private var isSearchExpanded: Bool { appState.expandedSearchRowIDs[store.id]?.contains(row.id) ?? false }

    private var searchQuery: Binding<String> {
        Binding(
            get: { appState.searchQueries[store.id]?[row.id] ?? "" },
            set: { appState.searchQueries[store.id, default: [:]][row.id] = $0 }
        )
    }

    /// Store accent when it passes a 3:1 check against the panel surface; otherwise the
    /// native macOS caret color (dark navy on dark mode, pale yellow on light mode, etc.).
    private var searchCaretColor: NSColor {
        // Shopify chrome is always a light surface regardless of system appearance.
        let surfaceScheme: ColorScheme = isShopify ? .light : colorScheme
        return store.color.contrastsWithPanelSurface(colorScheme: surfaceScheme)
            ? NSColor(hex: store.colorHex)
            : .controlAccentColor
    }

    private var hasTrailingActions: Bool { row.createAction != nil || row.supportsSearch }

    private var isShopify: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(row.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(
                            isShopify
                                ? (isActive ? Theme.Shopify.textPrimary : Theme.Shopify.textMeta)
                                : (isActive ? Theme.textBody : Theme.textMeta40)
                        )
                    Text(row.title)
                        .font(.panel(12, shopify: isShopify))
                        .foregroundStyle(labelColor)
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 3)
                // Scoped to just the link's own zone — the "+"/search buttons sit outside
                // this contentShape entirely (as separate HStack siblings below), so clicking
                // between/around them can never fall through and register as opening the link.
                // Padding lives here (not on the outer HStack) so the buttons' own
                // `maxHeight: .infinity` stretches to match this row's *full* height,
                // including the padding, instead of leaving a dead strip top/bottom.
                .contentShape(Rectangle())
                .onTapGesture {
                    becomeActive()
                    openLink()
                }

                // Its own tight-spacing group — the outer HStack's spacing (6) only applies
                // between the link zone and this whole cluster, not within it.
                // Intrinsic glyph widths + equal hit-only extensions toward a non-interactive
                // divider: equal visual gap, no dead zone for tooltips/taps.
                let hasSearch = row.supportsSearch
                let hasCreate = row.createAction != nil
                let hasBothTrailingActions = hasSearch && hasCreate
                let trailingActionHalfGap: CGFloat = 3
                HStack(alignment: .center, spacing: 0) {
                    if hasSearch {
                        PillSegment(
                            isActive: isSearchExpanded,
                            hitExpandTrailing: hasBothTrailingActions ? trailingActionHalfGap : 0
                        ) {
                            becomeActive()
                            if isSearchExpanded {
                                appState.expandedSearchRowIDs[store.id]?.remove(row.id)
                                if focusedRowSearchID.wrappedValue == row.id {
                                    // Only clear the shared focus if it was actually this row's —
                                    // collapsing a row that's expanded-but-unfocused (another row
                                    // currently has focus) must not steal focus away from it.
                                    focusedRowSearchID.wrappedValue = nil
                                }
                            } else {
                                appState.expandedSearchRowIDs[store.id, default: []].insert(row.id)
                                focusedRowSearchID.wrappedValue = row.id
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.panel(10, weight: .medium, shopify: isShopify))
                        }
                        .hoverTooltip(
                            "Toggle search",
                            shortcut: appState.settings.toggleLinkSearchHotkey,
                            gap: 1
                        )
                    }
                    if hasBothTrailingActions {
                        // Zero-width join so search/+ hit expansions meet with no dead strip;
                        // divider is drawn centered on that join (equal gap each side).
                        // Slightly stronger than `Theme.divider` / Polaris hairline so it
                        // still reads against the row’s hover/active fill.
                        Color.clear
                            .frame(width: 0, height: 12)
                            .overlay {
                                Rectangle()
                                    .fill(
                                        isShopify
                                            ? Color(hex: "d8d8d8")
                                            : Color.adaptive(light: .black.opacity(0.14), dark: .white.opacity(0.18))
                                    )
                                    .frame(width: 1, height: 12)
                            }
                            .allowsHitTesting(false)
                    }
                    if let createAction = row.createAction {
                        PillSegment(
                            hitExpandLeading: hasBothTrailingActions ? trailingActionHalfGap : 0
                        ) {
                            becomeActive()
                            guard let url = row.createURL(for: store.myshopifyDomain) else { return }
                            openStoreLink(url)
                        } label: {
                            Text("+")
                                .font(.panel(10, weight: .medium, shopify: isShopify))
                        }
                        .hoverTooltip(
                            "Create new \(createAction.noun)",
                            shortcut: appState.settings.openCreateLinkHotkey,
                            gap: 1
                        )
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, hasTrailingActions ? 3 : 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                pointerInside = hovering
                if hovering { tryActivateFromHover() }
            }
            .onChange(of: appState.cardLinkHoverArmed) { _, armed in
                if armed && pointerInside { becomeActive() }
            }

            if isSearchExpanded {
                Rectangle()
                    .fill(isShopify ? Theme.Shopify.hairline : Theme.divider)
                    .frame(height: 1)

                // Custom placeholder: AppKit's cell placeholder jumps when the field
                // editor attaches on focus; a SwiftUI label stays put.
                ZStack(alignment: .leading) {
                    if searchQuery.wrappedValue.isEmpty {
                        Text("Search")
                            .font(.panel(11.5, shopify: isShopify))
                            .foregroundStyle(isShopify ? Theme.Shopify.textMeta : Theme.textMeta30)
                            .allowsHitTesting(false)
                    }
                    CaretTintedTextField(
                        text: searchQuery,
                        caretColor: searchCaretColor,
                        onSubmit: submitSearch,
                        selectAllGeneration: appState.linkSearchSelectAllRowID == row.id
                            ? appState.linkSearchSelectAllGeneration
                            : 0
                    )
                        .focused(focusedRowSearchID, equals: row.id)
                        .focusEffectDisabled()
                        .onExitCommand {
                            appState.expandedSearchRowIDs[store.id]?.remove(row.id)
                            if focusedRowSearchID.wrappedValue == row.id {
                                focusedRowSearchID.wrappedValue = nil
                            }
                        }
                        .onKeyPress { keyPress in
                            if appState.settings.toggleLinkSearchHotkey.matches(keyPress) {
                                return onToggleLinkSearchKey() ? .handled : .ignored
                            }
                            return .ignored
                        }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 26)
            }
        }
        .background {
            // Active highlight is AppState-driven only — never stack hover + arrow
            // highlights. Expanded search without active focus keeps no fill.
            if isActive {
                RoundedRectangle(cornerRadius: 5, style: isShopify ? .circular : .continuous)
                    .fill(isShopify ? Theme.Shopify.controlFill : Theme.controlFill)
            }
        }
    }

    private var labelColor: Color {
        if isShopify {
            return Theme.Shopify.textPrimary
        }
        return isActive ? Theme.textPrimary : Theme.textBody
    }

    private func tryActivateFromHover() {
        appState.focusCardLink(section: section, rowIndex: rowIndex, fromHover: true)
    }

    private func becomeActive() {
        appState.focusCardLink(section: section, rowIndex: rowIndex)
    }

    private func openLink() {
        guard let url = row.url(for: store.myshopifyDomain) else { return }
        openStoreLink(url)
    }

    private func submitSearch() {
        guard let url = row.searchURL(for: store.myshopifyDomain, query: searchQuery.wrappedValue) else { return }
        openStoreLink(url)
        // `openStoreLink` hands focus to the browser, which can leave this row's
        // `@FocusState` binding stuck non-nil (the window resigning key status doesn't
        // reliably clear it) — that would otherwise permanently block the global
        // keyboard-nav guard in `PanelView`. Release it explicitly rather than relying
        // on SwiftUI to notice the field lost real focus.
        if focusedRowSearchID.wrappedValue == row.id {
            focusedRowSearchID.wrappedValue = nil
        }
    }
}

/// One "+" or search tap target — a bare glyph, neutral-colored like the row's own
/// leading icon, with no pill background of its own. Stretches to the row's full height
/// (via `frame` before `contentShape`, so the hit area actually grows with it, not just
/// the glyph) so there's no dead space above/below it that would otherwise fall through
/// to the row's own link tap gesture.
///
/// `hitExpandLeading` / `hitExpandTrailing` add clear space that is part of the hit
/// target (and tooltip hover) without changing the glyph’s own padding — used so
/// search/+ meet across a non-interactive divider.
private struct PillSegment<Label: View>: View {
    var isActive: Bool = false
    var hitExpandLeading: CGFloat = 0
    var hitExpandTrailing: CGFloat = 0
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            if hitExpandLeading > 0 {
                Color.clear.frame(width: hitExpandLeading)
            }
            label()
                .foregroundStyle(
                    appState.settings.widgetThemePreference.isShopify
                        ? (isHovering || isActive ? Theme.Shopify.textPrimary : Theme.Shopify.textMeta)
                        : (isHovering || isActive ? Theme.textBody : Theme.textMeta40)
                )
                .padding(.horizontal, 2)
            if hitExpandTrailing > 0 {
                Color.clear.frame(width: hitExpandTrailing)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: action)
    }
}
