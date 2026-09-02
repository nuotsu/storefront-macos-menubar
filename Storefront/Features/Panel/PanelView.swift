import SwiftUI
import AppKit

struct PanelView: View {
    @Environment(AppState.self) private var appState
    @State private var safeTriangle = SafeTriangleController()
    @State private var hoverTooltips = HoverTooltipController()
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedRowSearchID: String?
    /// Non-text focus target so shortcuts keep working after the search field is blurred
    /// (e.g. after ⌘1–9), without the text field swallowing ⌘A / ⌘O.
    @FocusState private var panelFocused: Bool
    /// When true, clearing `focusedRowSearchID` must not bounce focus to the rail search
    /// (⌃S collapse parks on the panel instead).
    @State private var suppressRailSearchRefocus = false
    @Environment(\.openWindow) private var openWindow

    /// Detached floating window (under mouse, or menu bar icon hidden).
    private var isFloatingPanel: Bool {
        Theme.isFloatingPanel(settings: appState.settings)
    }

    /// `.system` resolves against `NSApp.effectiveAppearance` at call time, so nothing
    /// stored changes when macOS flips Light↔Dark. Reading the revision registers the
    /// dependency that makes this re-evaluate on a system flip.
    /// Shopify theme locks the widget to light Polaris (Appearance preference is ignored).
    private var resolvedColorScheme: ColorScheme {
        _ = appState.systemAppearanceRevision
        if appState.settings.widgetThemePreference.isShopify {
            return .light
        }
        return appState.settings.appearancePreference.colorScheme
    }

    private var widgetChrome: WidgetChrome {
        WidgetChrome.current(settings: appState.settings)
    }

    private var panelCornerRadius: CGFloat {
        isFloatingPanel ? Theme.floatingPanelCornerRadius : 0
    }

    @ViewBuilder
    private var panelChromeBackground: some View {
        switch widgetChrome {
        case .shopify:
            Theme.Shopify.pageBackground
        case .macOSOpaque:
            Theme.panelOpaqueFill
        case .macOSGlass:
            if isFloatingPanel {
                // No NSPopover vibrancy behind us — supply glass chrome for the frame.
                // allowsHitTesting(false) is belt-and-suspenders; the NSView also
                // passthrough-hitTests (see SidebarGlassBackground).
                SidebarGlassBackground(
                    cornerRadius: panelCornerRadius,
                    material: .popover,
                    blendingMode: .behindWindow
                )
                .allowsHitTesting(false)
            }
        }
    }

    /// The right panel's frame is fully determined by fixed layout constants (not
    /// measured dynamically) — a `GeometryReader` here proved unreliable, since its
    /// preference never committed a non-zero value through the conditionally-built
    /// (`if store != nil { … } else { … }`) content above it.
    private var rightPanelFrame: CGRect {
        let originX = Theme.railInset + Theme.railWidth + Theme.railGap
        return CGRect(x: originX, y: 0, width: Theme.panelSize.width - originX, height: Theme.panelSize.height)
    }

    var body: some View {
        HStack(spacing: Theme.railGap) {
            StoreRailView(searchFocused: $searchFocused)
                .padding(.leading, Theme.railInset)
                .padding(.vertical, Theme.railInset)
                // Edge-ring void (rail insets): drag without changing layout. Rail controls
                // sit above this and keep their own hits.
                .background {
                    if isFloatingPanel {
                        Color.clear
                            .contentShape(Rectangle())
                            .modifier(PanelWindowDragModifier(enabled: true))
                    }
                }

            if let store = appState.selectedStore {
                // Keep identity across hover-select so the detail column updates in place
                // instead of tearing down cards/favicons on every rail scrub.
                StoreDetailView(
                    store: store,
                    focusedRowSearchID: $focusedRowSearchID,
                    onToggleLinkSearchKey: { performToggleLinkSearch() }
                )
            } else {
                emptyState
                    .contentShape(Rectangle())
                    .modifier(PanelWindowDragModifier(enabled: isFloatingPanel))
            }
        }
        .coordinateSpace(name: "panel")
        .background(
            MouseTrackingOverlay { point in
                safeTriangle.handleMouseMoved(to: point)
                appState.notePanelMouseMoved()
            }
            .allowsHitTesting(false)
        )
        .environment(safeTriangle)
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            safeTriangle.updateRowFrames(frames)
        }
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        // Catch rail-gap / page-void hits that aren't claimed by the rail or detail column.
        .background {
            if isFloatingPanel {
                Color.clear
                    .contentShape(Rectangle())
                    .modifier(PanelWindowDragModifier(enabled: true))
            }
        }
        // Menu bar popover: root stays clear so NSPopover vibrancy fills body + beak
        // (opaque mode fills the frame). Floating (menu bar off): provide our own
        // rounded chrome since there is no popover arrow / system beak.
        .background { panelChromeBackground }
        .modifier(
            FloatingPanelChromeModifier(
                isFloating: isFloatingPanel,
                cornerRadius: panelCornerRadius,
                cornerStyle: widgetChrome.cornerStyle
            )
        )
        // After the floating clip so tooltips aren't cropped by the rounded mask;
        // the host still clamps into the panel with an edge margin.
        .hoverTooltipContainer(controller: hoverTooltips)
        .preferredColorScheme(resolvedColorScheme)
        .focusable()
        .focused($panelFocused)
        .focusEffectDisabled()
        .onAppear {
            resetPanelInteractionToRail()
            safeTriangle.updateRightPanelFrame(rightPanelFrame)
            safeTriangle.configure { rowID in
                if let store = appState.stores.first(where: { $0.id == rowID }) {
                    appState.select(store)
                }
            }
            safeTriangle.updateSelectedRowID(appState.selectedStoreID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            // Hosting controller is reused across opens — onAppear won't fire again.
            resetPanelInteractionToRail()
        }
        .onChange(of: appState.selectedStoreID) { _, newValue in
            safeTriangle.updateSelectedRowID(newValue)
            // Only steal focus when a TextField would swallow panel shortcuts —
            // skip the churn on every hover-select while the panel is already focused.
            if searchFocused || focusedRowSearchID != nil {
                moveKeyboardFocusToPanel()
            }
        }
        .onChange(of: focusedRowSearchID) { oldValue, newValue in
            // A row's search field just lost real keyboard focus (Escape, submit, or
            // collapsing via the magnifying-glass control) — restore focus to the rail's
            // search field so *something* always holds it. Without this, `.onKeyPress`
            // below has no focused responder to fire from at all, silently breaking every
            // keyboard shortcut (arrows included) until the panel is closed and reopened.
            // ⌃S collapse sets `suppressRailSearchRefocus` and parks on the panel instead.
            if oldValue != nil && newValue == nil, !suppressRailSearchRefocus {
                searchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    /// Blur text fields and park focus on the panel so shortcut chords aren't eaten by
    /// `TextField` (⌘A select-all, typing, etc.).
    private func moveKeyboardFocusToPanel() {
        focusedRowSearchID = nil
        searchFocused = false
        // Must drop to `false` before the next-turn `true`. Setting `true` while a row
        // search `NSTextView` is still first responder fails silently; a later
        // `panelFocused = true` is then a no-op and `.onKeyPress` dies (no arrows).
        panelFocused = false
        DispatchQueue.main.async {
            self.searchFocused = false
            self.focusedRowSearchID = nil
            // Same park as `AppDelegate.showFloatingPanel` — hosting view must be
            // AppKit first responder before SwiftUI focus can attach.
            if let window = NSApp.keyWindow {
                window.makeFirstResponder(window.contentView)
            }
            self.panelFocused = true
        }
    }

    /// Store list active, cards inactive — ready for ↑↓ store navigation.
    private func resetPanelInteractionToRail() {
        appState.exitToRail()
        moveKeyboardFocusToPanel()
    }

    private func focusStoreSearch() {
        appState.exitToRail()
        focusedRowSearchID = nil
        panelFocused = false
        searchFocused = true
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    /// Shared by panel `onKeyPress` and the row-search `TextField` (which can swallow ⌃S
    /// before it bubbles). Returns whether the shortcut was applicable.
    ///
    /// Cycle: collapsed → expand+focus; expanded but unfocused → focus only;
    /// expanded and focused → collapse.
    @discardableResult
    private func performToggleLinkSearch() -> Bool {
        // Block only while typing in the rail store search with no active card link.
        // Hover/click puts `focusArea` into `.cards`, so ⌃S still works for mouse users
        // even if the rail search still holds text focus.
        if searchFocused && focusedRowSearchID == nil && appState.focusArea != .cards {
            return false
        }
        guard let rowID = appState.focusedSearchableRowID() else { return false }

        // Already open but caret isn't in the field (e.g. arrowed onto a row left expanded):
        // focus first; don't collapse until a later ⌃S while focused.
        if appState.isFocusedLinkSearchExpanded(), focusedRowSearchID != rowID {
            suppressRailSearchRefocus = false
            focusLinkSearchField(rowID, selectAll: true)
            return true
        }

        guard let result = appState.toggleSearchForFocusedLink() else { return false }
        if result.isNowExpanded {
            suppressRailSearchRefocus = false
            focusLinkSearchField(result.rowID, selectAll: true)
        } else {
            // Keep suppress up until panel focus has re-attached on the next turn —
            // clearing it in the same async flush as `moveKeyboardFocusToPanel` can let
            // `onChange(focusedRowSearchID)` bounce focus onto the rail search.
            suppressRailSearchRefocus = true
            moveKeyboardFocusToPanel()
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    suppressRailSearchRefocus = false
                }
            }
        }
        return true
    }

    /// Puts the caret in the expanded row search — sync + next-turn so the field exists
    /// in the hierarchy after expand before `@FocusState` commits. When `selectAll` is
    /// set, leftover query text is selected so typing replaces it.
    private func focusLinkSearchField(_ rowID: String, selectAll: Bool = false) {
        panelFocused = false
        searchFocused = false
        focusedRowSearchID = rowID
        DispatchQueue.main.async {
            self.panelFocused = false
            self.searchFocused = false
            self.focusedRowSearchID = rowID
            if selectAll {
                self.appState.requestLinkSearchSelectAll(rowID: rowID)
            }
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let typingInSearch = searchFocused || focusedRowSearchID != nil

        // Store-search focus only when not already typing in a field.
        if !typingInSearch, appState.settings.focusSearchHotkey.matches(keyPress) {
            focusStoreSearch()
            return .handled
        }
        // Link-search toggle stays available while a row search is focused (so ⌃S
        // can collapse/re-expand continuously), but not while the rail store search
        // is focused.
        if appState.settings.toggleLinkSearchHotkey.matches(keyPress) {
            return performToggleLinkSearch() ? .handled : .ignored
        }

        if keyPress.modifiers.contains(.command) {
            if keyPress.key == "q" {
                NSApp.terminate(nil)
                return .handled
            }
            if let digit = Int(String(keyPress.key.character)), (1...9).contains(digit) {
                appState.selectStore(atShortcutIndex: digit)
                moveKeyboardFocusToPanel()
                return .handled
            }
            return .ignored
        }

        // Escape from the rail search returns to the store list (not close / stay in field).
        if keyPress.key == .escape, searchFocused {
            appState.exitToRail()
            moveKeyboardFocusToPanel()
            return .handled
        }

        // While typing in the rail or row search field, let the TextField handle
        // keys (including A/O/H/arrows) instead of panel shortcuts / grid nav.
        guard !typingInSearch else { return .ignored }

        if appState.settings.openAdminHotkey.matches(keyPress) {
            appState.openSelectedAdmin()
            return .handled
        }
        if appState.settings.openOnlineStoreHotkey.matches(keyPress) {
            appState.openSelectedOnlineStore()
            return .handled
        }
        if appState.settings.openSupportHotkey.matches(keyPress) {
            appState.openSelectedSupport()
            return .handled
        }
        if appState.settings.openCreateLinkHotkey.matches(keyPress) {
            appState.openFocusedCreateLink()
            return .handled
        }

        switch keyPress.key {
        case .upArrow:
            if appState.focusArea == .rail {
                appState.selectAdjacentStore(offset: -1)
            } else {
                appState.moveRowFocus(offset: -1)
            }
            return .handled
        case .downArrow:
            if appState.focusArea == .rail {
                appState.selectAdjacentStore(offset: 1)
            } else {
                appState.moveRowFocus(offset: 1)
            }
            return .handled
        case .leftArrow:
            if appState.focusArea == .rail {
                appState.enterCards()
            } else {
                appState.moveCardFocus(offset: -1)
            }
            return .handled
        case .rightArrow:
            if appState.focusArea == .rail {
                appState.enterCards()
            } else {
                appState.moveCardFocus(offset: 1)
            }
            return .handled
        case .return:
            guard appState.focusArea == .cards else { return .ignored }
            appState.openFocusedLink()
            return .handled
        case .escape:
            if appState.focusArea == .cards {
                appState.exitToRail()
                moveKeyboardFocusToPanel()
            } else {
                AppDelegate.shared?.closePanel()
            }
            return .handled
        default:
            return .ignored
        }
    }

    private var emptyState: some View {
        let shopify = appState.settings.widgetThemePreference.isShopify
        return VStack(spacing: 8) {
            Text("No stores yet")
                .font(.panel(13, weight: .semibold, shopify: shopify))
            Text("Add a store from Settings to get started.")
                .font(.panel(11.5, shopify: shopify))
                .foregroundStyle(shopify ? Theme.Shopify.textSecondary : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rounded clip for the detached (menu bar off) panel only —
/// leave the menu-bar NSPopover path untouched so the system beak still composites.
private struct FloatingPanelChromeModifier: ViewModifier {
    let isFloating: Bool
    let cornerRadius: CGFloat
    var cornerStyle: RoundedCornerStyle = .continuous

    func body(content: Content) -> some View {
        if isFloating {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle))
        } else {
            content
        }
    }
}

#Preview {
    PanelView()
        .environment(AppState())
}
