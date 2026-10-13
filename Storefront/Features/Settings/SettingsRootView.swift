import AppKit
import SwiftUI

enum SettingsWindowMetrics {
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 480
    static let idealWidth: CGFloat = 780
    /// Tall enough for Stores (list + favicon/CSV rows) without feeling cramped.
    static let idealHeight: CGFloat = 780
}

/// Native `NavigationSplitView` settings shell — system Liquid Glass sidebar,
/// and traffic lights, with no sidebar toggle. Search lives in the sidebar header.
struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""
    /// Bumped when the sidebar opens/closes so toolbar polish can run a short
    /// overflow-suppress burst without a permanent per-frame timer.
    @State private var overflowBurstToken: UInt = 0

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `.system` resolves against `NSApp.effectiveAppearance` at call time, so nothing
    /// stored changes when macOS flips Light↔Dark. Reading the revision registers the
    /// dependency that makes this re-evaluate on a system flip.
    private var resolvedColorScheme: ColorScheme {
        _ = appState.systemAppearanceRevision
        return appState.settings.appearancePreference.colorScheme
    }

    private var searchHits: [SettingsSearchHit] {
        SettingsSearchIndex.hits(
            query: searchText,
            storeNames: appState.stores.map(\.displayName),
            sectionTitles: SectionID.allCases.map(\.title)
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            // No outer ScrollView — Stores uses List, which collapses to zero height
            // when nested in an unbounded scroll container. Sections is ScrollView-based.
            // Each pane owns `.settingsTopScrollEdgeBlur()` on its scroller so the
            // titleband progressive blur tracks the real scroll view (not this wrapper).
            detailPane(for: appState.selectedSettingsTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(appState.selectedSettingsTab.title)
        }
        .frame(
            minWidth: SettingsWindowMetrics.minWidth,
            idealWidth: SettingsWindowMetrics.idealWidth,
            minHeight: SettingsWindowMetrics.minHeight,
            idealHeight: SettingsWindowMetrics.idealHeight
        )
        .preferredColorScheme(resolvedColorScheme)
        .id(appState.appearanceRevision)
        .background(
            SettingsToolbarConfigurator(
                paneTitle: appState.selectedSettingsTab.title,
                overflowBurstToken: overflowBurstToken
            )
        )
        .onChange(of: columnVisibility) { _, _ in
            // Brief high-frequency overflow suppress only while the sidebar animates.
            overflowBurstToken &+= 1
        }
        .onAppear {
            AppDelegate.shared?.applyAppearancePreference(appState.settings.appearancePreference)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        // `@Observable` has no projected value, so the selection binding goes through
        // a local @Bindable rather than `$appState` directly.
        @Bindable var appState = appState

        Group {
            if isSearching {
                // One `searchHits` evaluation per body — it re-runs the whole index
                // filter, and reading the computed property twice ran it on every
                // keystroke twice over.
                searchList(searchHits)
            } else {
                List(SettingsTab.allCases, selection: $appState.selectedSettingsTab) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        SettingsTabIcon(tab: tab, size: 16)
                    }
                    .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        // Pins search above the list (safeAreaBar on Tahoe) so rows scroll under it
        // with progressive blur instead of painting on top.
        .detailHeaderSafeAreaBar {
            sidebarSearchField
        }
    }

    /// Separate list without a selection binding — avoids duplicate-tag crashes when
    /// multiple hits map to the same `SettingsTab`.
    private func searchList(_ hits: [SettingsSearchHit]) -> some View {
        List {
            if hits.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hits) { hit in
                    Button {
                        appState.selectedSettingsTab = hit.tab
                        searchText = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .foregroundStyle(.primary)
                            Text(hit.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sidebarSearchField: some View {
        HStack(spacing: 6) {
            Image("SearchIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if isSearching {
                Button {
                    searchText = ""
                } label: {
                    Image("XIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(1)
    }

    @ViewBuilder
    private func detailPane(for tab: SettingsTab) -> some View {
        switch tab {
        case .stores:
            StoresTabView()
        case .sections:
            SectionsTabView()
        case .keybindings:
            KeybindingsTabView()
        case .howToUse:
            HowToUseTabView()
        case .general:
            GeneralTabView()
        case .appearance:
            AppearanceTabView()
        case .about:
            AboutTabView()
        }
    }
}

/// Pane icon from the bundled Polaris asset.
struct SettingsTabIcon: View {
    let tab: SettingsTab
    let size: CGFloat

    var body: some View {
        Image(tab.iconName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Light toolbar polish (do not replace SwiftUI's toolbar)

/// Locks icon-only mode, syncs the window title to the active pane, and suppresses
/// the titlebar hairline + toolbar overflow bubble. Never assigns `window.toolbar` —
/// replacing SwiftUI's toolbar causes KVO crashes and can strip traffic lights /
/// the sidebar toggle.
private struct SettingsToolbarConfigurator: NSViewRepresentable {
    var paneTitle: String
    /// Incremented on sidebar open/close to start a short overflow-suppress burst.
    var overflowBurstToken: UInt

    final class Coordinator {
        private var burstTimer: Timer?
        private var burstDeadline: CFAbsoluteTime = 0
        private var lastBurstToken: UInt = 0
        private var didApplyChrome = false
        weak var trackedWindow: NSWindow?
        /// Strong cache of the titlebar/toolbar subtree; cleared when the window changes.
        var cachedTitlebarRoot: NSView?
        var paneTitle: String = ""

        /// Whether `track` would actually do anything. `updateNSView` runs on every
        /// SwiftUI update of the Settings tree, so this avoids scheduling a main-queue
        /// hop when nothing it looks at has changed. Deliberately conservative: while
        /// the chrome has not been applied yet, or the view has no window, it always
        /// says yes — that is the case the deferred `track` exists to handle.
        func needsTracking(window: NSWindow?, paneTitle: String, overflowBurstToken: UInt) -> Bool {
            window !== trackedWindow
                || !didApplyChrome
                || self.paneTitle != paneTitle
                || overflowBurstToken != lastBurstToken
        }

        func track(_ window: NSWindow?, paneTitle: String, overflowBurstToken: UInt) {
            self.paneTitle = paneTitle
            let windowChanged = window !== trackedWindow
            if windowChanged {
                stopBurst()
                trackedWindow = window
                cachedTitlebarRoot = nil
                didApplyChrome = false
            }

            if windowChanged || !didApplyChrome {
                applyChrome(window, paneTitle: paneTitle)
                didApplyChrome = window != nil
            } else if !paneTitle.isEmpty, window?.title != paneTitle {
                window?.title = paneTitle
            }

            if overflowBurstToken != lastBurstToken {
                lastBurstToken = overflowBurstToken
                startOverflowBurst()
            }
        }

        deinit {
            stopBurst()
        }

        private func startOverflowBurst() {
            burstDeadline = CFAbsoluteTimeGetCurrent() + 0.45
            guard burstTimer == nil else { return }

            // ~60Hz, toolbar subtree only — avoids the lag from a permanent
            // full-window walk on every frame.
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if CFAbsoluteTimeGetCurrent() >= self.burstDeadline {
                    self.stopBurst()
                    return
                }
                self.suppressOverflowInTitlebar()
            }
            RunLoop.main.add(timer, forMode: .common)
            burstTimer = timer

            // Immediate first pass so the opening frame is covered.
            suppressOverflowInTitlebar()
        }

        private func stopBurst() {
            burstTimer?.invalidate()
            burstTimer = nil
        }

        /// One-time / infrequent chrome setup (title, separators, toolbar mode).
        private func applyChrome(_ window: NSWindow?, paneTitle: String) {
            guard let window else { return }

            if !paneTitle.isEmpty, window.title != paneTitle {
                window.title = paneTitle
            }

            window.titlebarSeparatorStyle = .none
            Self.suppressSplitViewTitleSeparators(in: window)

            if let toolbar = window.toolbar {
                toolbar.displayMode = .iconOnly
                toolbar.allowsUserCustomization = false
                toolbar.showsBaselineSeparator = false
                if #available(macOS 15.0, *) {
                    toolbar.allowsDisplayModeCustomization = false
                }
                for item in toolbar.items {
                    item.visibilityPriority = .user
                }
            }

            let titlebar = titlebarRoot(in: window)
            Self.suppressOverflow(in: titlebar)
            Self.suppressHairlines(in: titlebar, window: window)
        }

        private func suppressOverflowInTitlebar() {
            guard let window = trackedWindow else { return }
            Self.suppressOverflow(in: titlebarRoot(in: window))
            if let toolbar = window.toolbar {
                for item in toolbar.items {
                    item.visibilityPriority = .user
                }
            }
        }

        private func titlebarRoot(in window: NSWindow) -> NSView {
            if let cached = cachedTitlebarRoot, cached.window === window {
                return cached
            }
            let root = window.contentView?.superview ?? window.contentView ?? NSView()
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                let name = NSStringFromClass(type(of: view))
                if name.contains("NSTitlebarContainerView") || name.contains("NSToolbarView") {
                    cachedTitlebarRoot = view
                    return view
                }
                stack.append(contentsOf: view.subviews)
            }
            cachedTitlebarRoot = root
            return root
        }

        private static func suppressHairlines(in root: NSView, window: NSWindow) {
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                let name = NSStringFromClass(type(of: view))
                if isTitlebarHairline(view, className: name, window: window) {
                    view.isHidden = true
                    view.alphaValue = 0
                    view.layer?.opacity = 0
                    view.setFrameSize(NSSize(width: view.frame.width, height: 0))
                }
                stack.append(contentsOf: view.subviews)
            }
        }

        /// Walk a subtree and force-hide any overflow / clipped-items chrome.
        static func suppressOverflow(in root: NSView) {
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                let name = NSStringFromClass(type(of: view))
                if isToolbarOverflowChrome(view, className: name) {
                    hideOverflowChrome(view)
                }
                stack.append(contentsOf: view.subviews)
            }
        }

        /// Detects the Sonoma+/Tahoe toolbar overflow indicator (`>>` / clipped-items
        /// chevron / glass bubble). Must not match the sidebar toggle.
        private static func isToolbarOverflowChrome(_ view: NSView, className: String) -> Bool {
            if className.localizedCaseInsensitiveContains("ClippedItems")
                || className.localizedCaseInsensitiveContains("ToolbarOverflow")
                || className.localizedCaseInsensitiveContains("OverflowButton")
                || className.localizedCaseInsensitiveContains("OverflowIndicator")
                || className.localizedCaseInsensitiveContains("ClippedItem")
                || (className.localizedCaseInsensitiveContains("Overflow")
                    && (className.localizedCaseInsensitiveContains("Toolbar")
                        || className.localizedCaseInsensitiveContains("Indicator")))
            {
                return true
            }

            let label = (
                (view as? NSButton)?.accessibilityLabel()
                    ?? view.accessibilityLabel()
                    ?? ""
            ).lowercased()
            let identifier = (view.identifier?.rawValue ?? "").lowercased()

            // Sidebar toggle — never hide.
            if label.contains("sidebar") || identifier.contains("sidebar") {
                return false
            }

            if label.contains("overflow")
                || label.contains("more toolbar")
                || label.contains("more items")
                || label.contains("clipped")
                || identifier.contains("overflow")
                || identifier.contains("clipped")
            {
                return true
            }

            if imageDescription(of: view).contains(where: { desc in
                desc.contains("chevron.forward.2")
                    || desc.contains("chevron.right.2")
                    || desc.contains("chevron.forward.to.line")
                    || desc.contains("overflow")
            }) {
                return true
            }

            // Glass bubble hosting the double-caret (Tahoe Liquid Glass toolbar).
            if (className.contains("GlassEffect") || className.contains("NSGlass"))
                && view.frame.width > 0
                && view.frame.width <= 64
                && subtreeContainsOverflowGlyph(view)
                && !viewerIsProtectedToolbarControl(view)
            {
                return true
            }

            // Settings' toolbar only needs the sidebar toggle. Small item viewers that
            // aren't the toggle / tracking separator are overflow chrome (`>>` / empty
            // glass bubble), often near the sidebar edge during column animation.
            if className.contains("NSToolbarItemViewer"),
               view.frame.width > 0,
               view.frame.width <= 56,
               !viewerIsProtectedToolbarControl(view)
            {
                return true
            }

            return false
        }

        private static func imageDescription(of view: NSView) -> [String] {
            var descs: [String] = []
            if let button = view as? NSButton, let image = button.image {
                descs.append(image.description.lowercased())
            }
            if let imageView = view as? NSImageView, let image = imageView.image {
                descs.append(image.description.lowercased())
            }
            return descs
        }

        private static func subtreeContainsOverflowGlyph(_ view: NSView) -> Bool {
            var stack: [NSView] = [view]
            while let current = stack.popLast() {
                for desc in imageDescription(of: current) {
                    if desc.contains("chevron.forward.2")
                        || desc.contains("chevron.right.2")
                        || desc.contains("overflow")
                    {
                        return true
                    }
                }
                stack.append(contentsOf: current.subviews)
            }
            return false
        }

        private static func viewerIsProtectedToolbarControl(_ view: NSView) -> Bool {
            if view.responds(to: NSSelectorFromString("item")),
               let item = view.value(forKey: "item") as? NSToolbarItem
            {
                let id = item.itemIdentifier.rawValue.lowercased()
                if id.contains("sidebar")
                    || id.contains("tracking")
                    || id.contains("flexiblespace")
                    || id.contains("spaces")
                {
                    return true
                }
                if id.contains("overflow") || id.contains("clipped") {
                    return false
                }
            }

            var stack: [NSView] = [view]
            while let current = stack.popLast() {
                let label = (
                    (current as? NSButton)?.accessibilityLabel()
                        ?? current.accessibilityLabel()
                        ?? ""
                ).lowercased()
                let identifier = (current.identifier?.rawValue ?? "").lowercased()
                let imageDesc = ((current as? NSButton)?.image?.description ?? "").lowercased()
                if label.contains("sidebar")
                    || identifier.contains("sidebar")
                    || imageDesc.contains("sidebar")
                    || identifier.contains("tracking")
                {
                    return true
                }
                stack.append(contentsOf: current.subviews)
            }
            return false
        }

        private static func isTitlebarHairline(_ view: NSView, className: String, window: NSWindow) -> Bool {
            if className.localizedCaseInsensitiveContains("TitlebarDecoration")
                || className.localizedCaseInsensitiveContains("TitlebarSeparator")
                || className.localizedCaseInsensitiveContains("ToolbarSeparator")
                || className.localizedCaseInsensitiveContains("TrackingSeparator")
            {
                return true
            }

            let frame = view.frame
            guard frame.height > 0, frame.height <= 1.5,
                  frame.width >= window.frame.width * 0.35
            else { return false }

            // Tahoe draws the titleband rule as a 1pt LayerBasedFillColorView inside
            // NSTitlebarBackgroundView — titlebarSeparatorStyle=.none does not remove it.
            if className.contains("LayerBasedFillColorView") {
                return true
            }

            var ancestor: NSView? = view.superview
            while let current = ancestor {
                let ancestorName = NSStringFromClass(type(of: current))
                if ancestorName.contains("NSTitlebarBackgroundView")
                    || ancestorName.contains("NSTitlebarContainerView")
                    || ancestorName.contains("NSTitlebarView")
                    || ancestorName.contains("NSToolbarView")
                {
                    return true
                }
                ancestor = current.superview
            }
            return false
        }

        private static func suppressSplitViewTitleSeparators(in window: NSWindow) {
            var controllers: [NSViewController] = []
            if let root = window.contentViewController {
                controllers.append(root)
            }
            var index = 0
            while index < controllers.count {
                let controller = controllers[index]
                index += 1
                controllers.append(contentsOf: controller.children)
                if let split = controller as? NSSplitViewController {
                    for item in split.splitViewItems {
                        item.titlebarSeparatorStyle = .none
                    }
                }
            }
        }

        private static func hideOverflowChrome(_ view: NSView) {
            var node: NSView? = view
            var depth = 0
            while let current = node, depth < 10 {
                let name = NSStringFromClass(type(of: current))
                if name.contains("NSToolbarView")
                    || name.contains("NSTitlebarView")
                    || name.contains("NSThemeFrame")
                {
                    break
                }
                // Hide before AppKit can paint this frame.
                current.isHidden = true
                current.alphaValue = 0
                current.wantsLayer = true
                current.layer?.opacity = 0
                current.layer?.isHidden = true
                current.setFrameSize(.zero)
                if name.contains("NSToolbarItemViewer")
                    || name.contains("ClippedItems")
                    || name.contains("Overflow")
                    || name.contains("GlassEffect")
                {
                    break
                }
                node = current.superview
                depth += 1
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.track(
                view.window,
                paneTitle: paneTitle,
                overflowBurstToken: overflowBurstToken
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.needsTracking(
            window: nsView.window,
            paneTitle: paneTitle,
            overflowBurstToken: overflowBurstToken
        ) else { return }

        DispatchQueue.main.async {
            context.coordinator.track(
                nsView.window,
                paneTitle: paneTitle,
                overflowBurstToken: overflowBurstToken
            )
        }
    }
}
