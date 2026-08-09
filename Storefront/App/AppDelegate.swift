import AppKit
import SwiftUI
import Sparkle
import Combine

extension Notification.Name {
    /// Posted by AppDelegate (and the panel rail) to open Settings — `PanelView`
    /// observes this and calls `@Environment(\.openWindow)`, and AppDelegate also
    /// brings any existing Settings window forward / triggers the Settings… menu item.
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    /// Posted whenever the widget panel is about to appear (popover or floating) so
    /// `PanelView` can reset rail focus even when the hosting controller is reused.
    static let panelWillShow = Notification.Name("panelWillShow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A direct reference views can reach for things like keeping the panel open —
    /// `NSApp.delegate as? AppDelegate` silently fails under `@NSApplicationDelegateAdaptor`
    /// (it's actually a `SwiftUI.AppDelegate` wrapper instance, a different type).
    static private(set) var shared: AppDelegate?

    /// Unique autosave name — must NOT be a generic `Item-N`. Those collide with
    /// Control Center's `NSStatusItem Visible Item-0`…`Item-11` (all set to 0 on this Mac),
    /// which hides the icon as if the user had ⌘-dragged it out of the menu bar.
    private static let statusItemAutosaveName = "com.humanmarketing.storefront.bag"
    /// Earlier builds gave every starred store its own status item; those defaults keys
    /// linger after the switch to a single grouped item.
    private static let legacyFavoriteAutosavePrefix = "com.humanmarketing.storefront.favorite."
    private static let statusItemPreferredPosition: Double = 48

    private var statusItem: NSStatusItem?
    /// Draws the glyph + starred-store favicons inside the one status item, so the whole
    /// group ⌘-drags as a unit.
    private var menuBarContentView: MenuBarContentView?
    private var faviconRevisionCancellable: AnyCancellable?
    private var popover: NSPopover?
    /// Borderless movable panel used when the menu bar icon is hidden (no popover beak).
    private var floatingPanel: StorefrontFloatingPanel?
    private var floatingPanelHosting: NSViewController?
    private var floatingClickOutsideMonitor: Any?
    private var floatingGlobalClickOutsideMonitor: Any?
    /// Suppresses click-outside dismiss briefly (⌘-click keep-open → browser activation).
    private var suppressFloatingClickOutsideUntil: Date?
    private static let floatingPanelCornerRadius = Theme.floatingPanelCornerRadius
    let appState = AppState()
    /// Lazy so `self` can be the user-driver delegate (gentle reminders → rail Update button).
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Always come up as a normal app first so the status bar will accept our item.
        // Accessory-only launch on multi-display Macs (esp. macOS 26) was leaving the
        // status item at a zero-height frame. We switch back to the user's Dock preference
        // after the item is created.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        clearStaleStatusItemVisibility()

        if appState.settings.showInMenuBar {
            ensureStatusItem()
        }

        observeFaviconRevisions()

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = Theme.panelSize
        pop.delegate = self
        let hosting = NSHostingController(
            rootView: PanelView().environment(appState)
        )
        hosting.view.wantsLayer = true
        hosting.view.focusRingType = .none
        pop.contentViewController = hosting
        popover = pop

        applyActivationPolicy()
        applyAppearancePreference(appState.settings.appearancePreference)
        applyPanelBackgroundOpacity(appState.settings.opaqueMenuBarWidget)
        // After launch — Tahoe can wedge if `applicationIconImage` runs in App.init.
        AppIconPreference.apply(appState.settings.appIconPreference)
        observeSystemAppearanceChanges()

        GlobalHotKeyManager.shared.register(appState.settings.globalHotkey) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Clicking the Dock icon (or re-opening while already running) surfaces Settings
    /// when no windows are visible — useful if the menu bar icon is missing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    /// Keep running as a menu-bar / hotkey app when Settings is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Store writes made in the last moments before quit are debounced (see
    /// `AppState.scheduleSaveStores`) — write them out or they're lost.
    func applicationWillTerminate(_ notification: Notification) {
        appState.flushPendingSaves()
    }

    // MARK: - Status item

    /// Wipe any leftover "hidden by ⌘-drag" flags for our autosave name (and a few
    /// generic names MenuBarExtra may have used in earlier builds).
    private func clearStaleStatusItemVisibility() {
        let defaults = UserDefaults.standard
        let keys = [
            "NSStatusItem Visible \(Self.statusItemAutosaveName)",
            "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)",
            "NSStatusItem Visible Item-0",
            "NSStatusItem Preferred Position Item-0",
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
        where key.contains(Self.legacyFavoriteAutosavePrefix) {
            defaults.removeObject(forKey: key)
        }
        // Force visible for our named item before creating it.
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.statusItemAutosaveName)")
    }

    func ensureStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = Self.statusItemAutosaveName
            item.isVisible = true

            if let button = item.button {
                // The glyph and favicons are drawn by `MenuBarContentView`; the button
                // itself stays empty so it can host them as one draggable unit.
                button.image = nil
                button.title = ""
                button.imagePosition = .imageOnly
                button.toolTip = "Storefront"
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])

                let content = MenuBarContentView(frame: button.bounds)
                content.autoresizingMask = [.width, .height]
                button.addSubview(content)
                menuBarContentView = content
            }

            statusItem = item
            applyMenuBarIcon()
            UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(Self.statusItemAutosaveName)")
            // Prefer a right-side slot (low value) so the icon isn't the first one
            // swallowed by the notch / application menu overflow on dual displays.
            if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)") == nil {
                UserDefaults.standard.set(
                    Self.statusItemPreferredPosition,
                    forKey: "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)"
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.warnIfMenuBarPermissionMissing()
            }
        } else {
            statusItem?.isVisible = true
        }

        syncMenuBarFavorites()
    }

    /// Updates the status item glyph from `menuBarIconPreference`.
    func applyMenuBarIcon() {
        guard let content = menuBarContentView else { return }
        let preference = appState.settings.menuBarIconPreference
        content.glyphImage = Self.menuBarStatusImage(for: preference)
        // Text fallback so something still shows if the asset fails to load.
        content.glyphFallbackTitle = content.glyphImage == nil ? "SF" : nil
        updateStatusItemLength()
    }

    /// Template menu-bar glyph sized to match typical status-item SF Symbols.
    private static func menuBarStatusImage(for preference: MenuBarIconPreference) -> NSImage? {
        if let symbolName = preference.systemSymbolName {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Storefront")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            return image
        }

        guard let assetName = preference.assetName,
              let source = NSImage(named: assetName)?.copy() as? NSImage else { return nil }
        // Polaris assets are authored at 20×20. Draw at exactly 20pt and keep only the
        // preserved SVG rep so AppKit re-rasters at the display scale — the catalog's
        // 20/40px bitmap stands-ins look soft when scaled or drawn off-pixel.
        let hasSVG = source.representations.contains {
            String(describing: type(of: $0)).contains("SVG")
        }
        if hasSVG {
            for rep in source.representations
                where !String(describing: type(of: rep)).contains("SVG") {
                source.removeRepresentation(rep)
            }
        }
        source.size = NSSize(width: 20, height: 20)
        source.isTemplate = true
        source.accessibilityDescription = "Storefront"
        return source
    }

    /// macOS 26 (Tahoe) added System Settings → Menu Bar permissions. Without the
    /// app enabled there, `NSStatusItem` still creates successfully but lands at
    /// `(0, -22)` with `button.window.screen == nil` and never appears.
    private func warnIfMenuBarPermissionMissing() {
        guard let button = statusItem?.button,
              let window = button.window else { return }
        let frame = window.frame
        let screenMissing = window.screen == nil
        let offScreen = frame.minY < 0 || frame.height < 1
        guard screenMissing || offScreen else { return }

        // Persist Dock so the user can still reach Settings after dismissing.
        if !appState.settings.showInDock {
            var settings = appState.settings
            settings.showInDock = true
            appState.settings = settings
            appState.saveSettings()
            applyActivationPolicy()
        }

        openSettingsWindow()

        let alert = NSAlert()
        alert.messageText = "Allow Storefront in the Menu Bar"
        alert.informativeText = """
            macOS is hiding the menu bar icon until Storefront is allowed under:

            System Settings → Menu Bar

            Turn Storefront on, then quit and reopen the app (or toggle Show in menu bar).
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Menu Bar Settings")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.MenuBar-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        menuBarContentView = nil
        self.statusItem = nil
    }

    // MARK: - Starred store favicons

    /// Redraws the grouped favicon strip for visible starred stores.
    func syncMenuBarFavorites() {
        guard let content = menuBarContentView, appState.settings.showInMenuBar else { return }
        let stores = appState.settings.showStarredStoresInMenuBar
            ? appState.menuBarFavoriteStores
            : []
        content.favorites = stores.map { store in
            MenuBarContentView.Favorite(
                id: store.id,
                title: store.displayName,
                image: Self.menuBarFavoriteImage(for: store)
            )
        }
        updateStatusItemLength()
    }

    private func updateStatusItemLength() {
        guard let statusItem, let content = menuBarContentView else { return }
        statusItem.length = content.totalWidth
    }

    private func observeFaviconRevisions() {
        faviconRevisionCancellable = FaviconStore.shared.$revision
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncMenuBarFavorites()
            }
    }

    /// Full-color menu-bar mark — cached favicon when available, else initials on the store accent.
    private static func menuBarFavoriteImage(for store: Store) -> NSImage {
        let dimension: CGFloat = 18
        let size = NSSize(width: dimension, height: dimension)
        let radius = dimension * 0.22
        let image = NSImage(size: size, flipped: false) { bounds in
            let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            path.addClip()

            if let favicon = FaviconStore.shared.image(for: store.id) {
                let sourceSize = favicon.size
                guard sourceSize.width > 0, sourceSize.height > 0 else {
                    Self.drawInitialsFallback(for: store, in: bounds)
                    return true
                }
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                if isDark {
                    NSColor.white.withAlphaComponent(Theme.faviconPlateDarkOpacity).setFill()
                    bounds.fill()
                }
                let scale = max(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
                let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
                let drawRect = NSRect(
                    x: bounds.midX - drawSize.width / 2,
                    y: bounds.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                favicon.draw(
                    in: drawRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                Self.drawInitialsFallback(for: store, in: bounds)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = store.displayName
        return image
    }

    private static func drawInitialsFallback(for store: Store, in bounds: NSRect) {
        let (r, g, b) = HexColor.components(store.colorHex)
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1).setFill()
        bounds.fill()

        let initials = store.initials as NSString
        let fontSize = max(8, bounds.height * 0.42)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        let textColor: NSColor = luma > 150 ? .black : .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSize = initials.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        initials.draw(at: point, withAttributes: attributes)
    }

    /// Always opens (or re-opens) the widget under `anchor` with `store` selected.
    private func reopenPanel(selecting store: Store, anchorRect: NSRect, in button: NSStatusBarButton) {
        appState.select(store)
        let wasVisible = isPanelVisible
        if wasVisible {
            closePanel()
        }
        // After a close, wait a turn so the transient popover fully tears down before re-show.
        let present = { [weak self] in
            guard let self else { return }
            self.preparePanelForShow()
            self.showPopover(anchorRect: anchorRect, in: button)
        }
        if wasVisible {
            DispatchQueue.main.async(execute: present)
        } else {
            present()
        }
    }

    private func showPopover(anchorRect: NSRect, in button: NSStatusBarButton) {
        guard let popover else {
            showFloatingPanel()
            return
        }
        // Optical nudge: glyphs often sit slightly right of midX; shift so the arrow lines up.
        var anchor = anchorRect
        anchor.origin.x += 1
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    /// The glyph's own slot within the grouped item, so the beak points at the icon
    /// rather than the middle of the icon-plus-favicons strip.
    private func glyphAnchorRect(in button: NSStatusBarButton) -> NSRect {
        menuBarContentView?.glyphFrame ?? button.bounds
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        // One button spans the glyph and every favicon — route by where it was clicked.
        if let event = NSApp.currentEvent,
           let content = menuBarContentView {
            let point = sender.convert(event.locationInWindow, from: nil)
            if let storeID = content.favoriteID(at: point),
               let store = appState.stores.first(where: { $0.id == storeID }),
               let rect = content.frame(forFavorite: storeID) {
                reopenPanel(selecting: store, anchorRect: rect, in: sender)
                return
            }
        }

        // Icon click always anchors to the status item (beak), ignoring Open under mouse.
        togglePanel(anchorToMenuBarIcon: true)
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Storefront", action: #selector(openPanelFromMenu), keyEquivalent: "")
        let (key, mask) = appState.settings.globalHotkey.nsMenuKeyEquivalent
        openItem.keyEquivalent = key
        openItem.keyEquivalentModifierMask = mask
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(settingsTabItem(title: "How to use", tab: .howToUse))

        let feedbackItem = NSMenuItem(title: "Send Feedback", action: #selector(sendFeedback(_:)), keyEquivalent: "")
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        menu.addItem(.separator())

        // Top-level peers (same group) — not nested under Settings.
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(settingsTabItem(title: "Stores", tab: .stores))
        menu.addItem(settingsTabItem(title: "Sections", tab: .sections))
        menu.addItem(settingsTabItem(title: "Keybindings", tab: .keybindings))

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let versionItem = NSMenuItem(title: "Current version: v\(shortVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Storefront", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // The button's own highlight sits behind our custom drawing — mirror it onto the
        // favicon plate (only) so it stays legible while the menu is up.
        menuBarContentView?.isHighlighted = true
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
        menuBarContentView?.isHighlighted = false
    }

    @objc private func openPanelFromMenu() {
        togglePanel(anchorToMenuBarIcon: true)
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow(tab: .general)
    }

    private func settingsTabItem(title: String, tab: SettingsTab) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openSettingsTabFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = tab
        return item
    }

    @objc private func openSettingsTabFromMenu(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? SettingsTab else { return }
        openSettingsWindow(tab: tab)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    // MARK: - Panel (hotkey + status click)

    private var isPanelVisible: Bool {
        (popover?.isShown ?? false) || (floatingPanel?.isVisible ?? false)
    }

    func togglePanel(anchorToMenuBarIcon: Bool = false) {
        if isPanelVisible {
            closePanel()
            return
        }

        preparePanelForShow()

        // Status-item click / menu: always popover under the icon (with beak).
        // Hotkey: honor Open under mouse, or fall back to floating when no icon.
        let preferFloating = !anchorToMenuBarIcon
            && (appState.settings.openUnderMouse || statusItem?.button == nil)

        if !preferFloating, let button = statusItem?.button {
            showPopover(anchorRect: glyphAnchorRect(in: button), in: button)
        } else {
            showFloatingPanel()
        }
    }

    /// Rail focus + keyboard parking before each open (hosting views are reused).
    private func preparePanelForShow() {
        appState.exitToRail()
        NotificationCenter.default.post(name: .panelWillShow, object: nil)
    }

    func closePanel() {
        appState.flushPendingSaves()
        popover?.performClose(nil)
        hideFloatingPanel()
    }

    private func showFloatingPanel() {
        let panel = ensureFloatingPanel()
        panel.setFrame(Self.clampedFloatingPanelFrame(near: NSEvent.mouseLocation), display: true)
        applyAppearancePreference(appState.settings.appearancePreference)
        applyPanelBackgroundOpacity(appState.settings.opaqueMenuBarWidget)
        NSApp.activate(ignoringOtherApps: true)
        // Brief grace so the opening interaction can't immediately dismiss us.
        suppressFloatingClickOutsideUntil = Date().addingTimeInterval(0.2)
        panel.makeKeyAndOrderFront(nil)
        // Ensure SwiftUI’s focus / key-press path is live (Escape, TextField, buttons).
        panel.makeFirstResponder(panel.contentView)
        startFloatingClickOutsideMonitor()
    }

    private func hideFloatingPanel() {
        stopFloatingClickOutsideMonitor()
        floatingPanel?.orderOut(nil)
    }

    private func ensureFloatingPanel() -> StorefrontFloatingPanel {
        if let floatingPanel { return floatingPanel }

        let size = Theme.panelSize
        // Borderless windows return `canBecomeKey == false` by default — without a
        // subclass override, SwiftUI never receives clicks or Escape.
        let panel = StorefrontFloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        // Drag only via explicit WindowDragGesture regions (ring, sidebar void, header) —
        // not card chrome or other non-control fills.
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.acceptsMouseMovedEvents = true

        // Not type-erased through AnyView — that would hide the panel's real view type
        // from SwiftUI's structural diffing at the hosting root.
        let hosting = NSHostingController(
            rootView: PanelView().environment(appState)
        )
        hosting.view.wantsLayer = true
        hosting.view.focusRingType = .none
        hosting.view.layer?.cornerRadius = Self.floatingPanelCornerRadius
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true
        panel.contentViewController = hosting
        panel.setContentSize(size)

        floatingPanelHosting = hosting
        floatingPanel = panel
        return panel
    }

    /// Places the panel so the pointer sits on the center of the first sidebar store row.
    private static func clampedFloatingPanelFrame(near mouse: NSPoint) -> NSRect {
        let size = Theme.panelSize
        let anchorOffset = Theme.floatingPanelFirstStoreRowCenter

        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        let anchor: NSPoint
        if let screen, NSMouseInRect(mouse, screen.frame, false) {
            anchor = mouse
        } else if let screen {
            anchor = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 4)
        } else {
            anchor = mouse
        }

        // AppKit origin is bottom-left; SwiftUI offset y is measured from the top.
        let frame = NSRect(
            x: anchor.x - anchorOffset.x,
            y: anchor.y - (size.height - anchorOffset.y),
            width: size.width,
            height: size.height
        )
        return frame.clamped(toVisibleFrameOf: screen)
    }

    private func startFloatingClickOutsideMonitor() {
        stopFloatingClickOutsideMonitor()

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            guard let panel = self.floatingPanel, panel.isVisible else { return }
            if let until = self.suppressFloatingClickOutsideUntil, Date() < until { return }

            let point = NSEvent.mouseLocation
            if panel.frame.contains(point) { return }
            // Keep open when interacting with Settings.
            if let settings = Self.findSettingsWindow(), settings.isVisible, settings.frame.contains(point) {
                return
            }
            // Ignore the event that opened us (same runloop turn).
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.closePanel()
            }
        }

        floatingClickOutsideMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            handler(event)
            return event
        }
        floatingGlobalClickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: handler
        )
    }

    private func stopFloatingClickOutsideMonitor() {
        if let floatingClickOutsideMonitor {
            NSEvent.removeMonitor(floatingClickOutsideMonitor)
            self.floatingClickOutsideMonitor = nil
        }
        if let floatingGlobalClickOutsideMonitor {
            NSEvent.removeMonitor(floatingGlobalClickOutsideMonitor)
            self.floatingGlobalClickOutsideMonitor = nil
        }
    }

    /// Temporarily stops the popover from auto-dismissing when it loses key status
    /// (which normally happens the instant a link click activates the browser) — used
    /// for the ⌘-click "keep open" behavior on links. Also suppresses floating
    /// click-outside dismiss for the same window.
    func keepPopoverOpenTemporarily() {
        popover?.behavior = .applicationDefined
        suppressFloatingClickOutsideUntil = Date().addingTimeInterval(1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.popover?.behavior = .transient
        }
    }

    // MARK: - Settings

    /// Opens the dedicated Settings `Window` (id: `"settings"`).
    func openSettingsWindow(tab: SettingsTab? = nil) {
        if let tab {
            appState.selectedSettingsTab = tab
        }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        // Bring an existing window forward, or invoke Settings… (Commands → openWindow)
        // when the panel hosting controller hasn't mounted yet.
        DispatchQueue.main.async {
            if let window = Self.findSettingsWindow() {
                window.appearance = self.appState.settings.appearancePreference.nsAppearance
                window.makeKeyAndOrderFront(nil)
            } else if let item = Self.settingsMenuItem(), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        }
    }

    private static func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first(where: isSettingsWindow)
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue ?? ""
        if id == "settings" || id.contains("settings") { return true }
        return window.title == "Settings"
    }

    private static func settingsMenuItem() -> NSMenuItem? {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return nil }
        return appMenu.items.first { item in
            item.keyEquivalent == "," || item.title.localizedCaseInsensitiveContains("settings")
        }
    }

    // MARK: - General toggles

    func setShowInMenuBar(_ enabled: Bool) {
        var settings = appState.settings
        settings.showInMenuBar = enabled
        appState.settings = settings
        appState.saveSettings()
        // Switching surfaces — close whichever panel is up so we don't leave a
        // floating window around after restoring the menu bar icon (or vice versa).
        closePanel()
        if enabled {
            clearStaleStatusItemVisibility()
            removeStatusItem()
            ensureStatusItem()
        } else {
            removeStatusItem()
        }
    }

    func setShowInDock(_ enabled: Bool) {
        var settings = appState.settings
        settings.showInDock = enabled
        appState.settings = settings
        appState.saveSettings()
        applyActivationPolicy()
        if enabled {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = appState.settings.showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    /// Keeps the menu bar panel popover, floating panel, and Settings windows on the
    /// chosen appearance without overriding `NSApp.appearance` (which would recolor
    /// the status icon). Shopify theme forces the panel to light aqua; Settings still
    /// follows the stored Appearance preference.
    func applyAppearancePreference(_ preference: AppearancePreference) {
        NSApp.appearance = nil
        let settingsAppearance = preference.nsAppearance
        let panelAppearance: NSAppearance = {
            if appState.settings.widgetThemePreference.isShopify {
                return NSAppearance(named: .aqua) ?? settingsAppearance
            }
            return settingsAppearance
        }()

        popover?.appearance = panelAppearance
        popover?.contentViewController?.view.appearance = panelAppearance

        floatingPanel?.appearance = panelAppearance
        floatingPanelHosting?.view.appearance = panelAppearance

        for window in NSApp.windows where Self.isSettingsWindow(window) {
            window.appearance = settingsAppearance
            window.contentView?.appearance = settingsAppearance
        }

        statusItem?.button?.window?.appearance = nil
        applyPanelBackgroundOpacity(appState.settings.opaqueMenuBarWidget)
    }

    /// Opaque / Shopify mode fills the hosting view so popover vibrancy doesn’t leak
    /// under SwiftUI; transparent mode stays clear so Liquid Glass / vibrancy show through.
    /// Also paints the popover frame view so the beak/triangle matches the panel body.
    func applyPanelBackgroundOpacity(_ opaque: Bool) {
        let isShopify = appState.settings.widgetThemePreference.isShopify
        let shouldFill = opaque || isShopify

        var fillColor: NSColor?
        if shouldFill {
            if isShopify {
                fillColor = Theme.Shopify.pageBackgroundNSColor
            } else if let view = popover?.contentViewController?.view
                ?? floatingPanelHosting?.view
            {
                view.effectiveAppearance.performAsCurrentDrawingAppearance {
                    fillColor = NSColor.windowBackgroundColor
                }
            } else {
                fillColor = NSColor.windowBackgroundColor
            }
        }

        let views = [
            popover?.contentViewController?.view,
            floatingPanelHosting?.view,
        ].compactMap { $0 }

        for view in views {
            view.wantsLayer = true
            view.layer?.backgroundColor = fillColor?.cgColor ?? NSColor.clear.cgColor
        }

        applyPopoverBeakBackground(fillColor: fillColor)
    }

    /// Colors the NSPopover window frame (the view that includes the arrow/beak).
    /// Content-view fill alone leaves the triangle on system vibrancy.
    private func applyPopoverBeakBackground(fillColor: NSColor?) {
        guard let contentView = popover?.contentViewController?.view else { return }
        // `contentView.superview` is the popover’s shaped frame view (body + beak).
        guard let frameView = contentView.superview else { return }

        frameView.wantsLayer = true
        if let fillColor {
            frameView.layer?.backgroundColor = fillColor.cgColor
        } else {
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func observeSystemAppearanceChanges() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemAppearanceDidChange() {
        // Defaults can lag this notification — resolve on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Light/Dark may switch between bundle chrome and an inset override
            // when system appearance flips.
            AppIconPreference.apply(self.appState.settings.appIconPreference)
            guard self.appState.settings.appearancePreference == .system else { return }
            self.applyAppearancePreference(.system)
            self.appState.noteSystemAppearanceChanged()
        }
    }

    // MARK: - Sparkle

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    @objc func sendFeedback(_ sender: Any?) {
        guard let url = URL(string: "https://storefront.nuotsu.dev/contact?source=context-menu") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension AppDelegate: NSPopoverDelegate {
    /// Frame view (incl. beak) only exists once the popover window is about to appear.
    func popoverWillShow(_ notification: Notification) {
        applyPanelBackgroundOpacity(appState.settings.opaqueMenuBarWidget)
    }
}

/// Everything the status item shows: the Storefront glyph, then the starred stores'
/// favicons on a subtle rounded plate. Living inside one `NSStatusItem` is what makes
/// the whole set ⌘-drag together instead of scattering across the menu bar.
private final class MenuBarContentView: NSView {
    struct Favorite {
        let id: UUID
        let title: String
        let image: NSImage
    }

    private enum Metrics {
        static let glyphWidth: CGFloat = 22
        static let glyphToGroupGap: CGFloat = 5
        static let groupPadding: CGFloat = 3.5
        static let iconSize: CGFloat = 16
        static let iconSpacing: CGFloat = 4
        static let groupCornerRadius: CGFloat = 6
        static let trailingInset: CGFloat = 3
    }

    var glyphImage: NSImage? {
        didSet { needsDisplay = true }
    }

    var glyphFallbackTitle: String? {
        didSet { needsDisplay = true }
    }

    var favorites: [Favorite] = [] {
        didSet {
            needsDisplay = true
            updateToolTipTracking()
        }
    }

    /// Mirrors the host button's highlight (right-click menu) for the favicon plate only —
    /// the glyph itself keeps its normal tint so it doesn't flash white on right-click.
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?

    /// Width the status item must reserve for the glyph plus the favicon plate.
    var totalWidth: CGFloat {
        guard !favorites.isEmpty else { return Metrics.glyphWidth }
        return Metrics.glyphWidth + Metrics.glyphToGroupGap + groupWidth + Metrics.trailingInset
    }

    var glyphFrame: NSRect {
        NSRect(x: 0, y: 0, width: Metrics.glyphWidth, height: bounds.height)
    }

    private var groupWidth: CGFloat {
        guard !favorites.isEmpty else { return 0 }
        let icons = CGFloat(favorites.count) * Metrics.iconSize
        let gaps = CGFloat(favorites.count - 1) * Metrics.iconSpacing
        return icons + gaps + Metrics.groupPadding * 2
    }

    private var groupFrame: NSRect? {
        guard !favorites.isEmpty else { return nil }
        let height = Metrics.iconSize + Metrics.groupPadding * 2
        return NSRect(
            x: Metrics.glyphWidth + Metrics.glyphToGroupGap,
            y: (bounds.height - height) / 2,
            width: groupWidth,
            height: height
        )
    }

    private func iconFrame(at index: Int) -> NSRect? {
        guard let groupFrame else { return nil }
        let x = groupFrame.minX + Metrics.groupPadding
            + CGFloat(index) * (Metrics.iconSize + Metrics.iconSpacing)
        return NSRect(
            x: x,
            y: bounds.midY - Metrics.iconSize / 2,
            width: Metrics.iconSize,
            height: Metrics.iconSize
        )
    }

    /// Store whose favicon (or its share of the plate) contains `point`.
    func favoriteID(at point: NSPoint) -> UUID? {
        guard let groupFrame, groupFrame.contains(point) else { return nil }
        for index in favorites.indices {
            guard var frame = iconFrame(at: index) else { continue }
            // Split the inter-icon spacing so the plate has no dead zones.
            frame = frame.insetBy(dx: -Metrics.iconSpacing / 2, dy: 0)
            if frame.minX <= point.x && point.x <= frame.maxX {
                return favorites[index].id
            }
        }
        return favorites.last?.id
    }

    func frame(forFavorite id: UUID) -> NSRect? {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return nil }
        return iconFrame(at: index)
    }

    /// Clicks (and ⌘-drag) belong to the status item button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Resolve colors against this view's appearance (menu bar light/dark), not the
        // app's. Pure black/white matches system status items better than labelColor,
        // which can read slightly gray / off-white in the menu bar.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tint: NSColor = isDark ? .white : .black
            drawGlyph(tint: tint)

            guard let groupFrame else { return }
            let plate = NSBezierPath(
                roundedRect: groupFrame,
                xRadius: Metrics.groupCornerRadius,
                yRadius: Metrics.groupCornerRadius
            )
            tint.withAlphaComponent(isHighlighted ? 0.22 : 0.12).setFill()
            plate.fill()

            for (index, favorite) in favorites.enumerated() {
                guard let frame = iconFrame(at: index) else { continue }
                favorite.image.draw(
                    in: frame,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            }
        }
    }

    private func drawGlyph(tint: NSColor) {
        if let glyphImage {
            let rect = pixelAlignedRect(for: glyphImage.size, centeredIn: glyphFrame)
            glyphImage.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none]
            )
            // Template glyphs carry no color of their own — tint them the way the
            // status bar would have, so they still flip with the menu bar appearance.
            if glyphImage.isTemplate {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
        } else if let glyphFallbackTitle {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: tint,
            ]
            let text = glyphFallbackTitle as NSString
            let size = text.size(withAttributes: attributes)
            let origin = pixelAlignedRect(for: size, centeredIn: glyphFrame).origin
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// Snap a centered draw rect to device pixels — half-pixel origins soften edges.
    private func pixelAlignedRect(for size: NSSize, centeredIn container: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let width = (size.width * scale).rounded() / scale
        let height = (size.height * scale).rounded() / scale
        let x = ((container.midX - width / 2) * scale).rounded() / scale
        let y = ((bounds.midY - height / 2) * scale).rounded() / scale
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Tooltips

    /// The button owns hit testing, so per-favicon tooltips come from tracking the
    /// pointer and retitling the button as it crosses each slot.
    private func updateToolTipTracking() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard !favorites.isEmpty else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let title = favoriteID(at: point)
            .flatMap { id in favorites.first(where: { $0.id == id })?.title }
        (superview as? NSButton)?.toolTip = title ?? "Storefront"
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (superview as? NSButton)?.toolTip = "Storefront"
    }
}

/// Borderless `NSPanel` that can become key/main so SwiftUI receives clicks and Escape.
private final class StorefrontFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Borderless windows skip AppKit’s automatic `constrainFrameRect` during drag,
    /// so every frame change must clamp here for a hard on-screen stop.
    override func setFrameOrigin(_ point: NSPoint) {
        var proposed = frame
        proposed.origin = point
        super.setFrameOrigin(Self.clampedFrame(proposed).origin)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(Self.clampedFrame(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(Self.clampedFrame(frameRect), display: displayFlag, animate: animateFlag)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect.clamped(toVisibleFrameOf: screen ?? Self.preferredScreen(for: frameRect))
    }

    private static func clampedFrame(_ frameRect: NSRect) -> NSRect {
        frameRect.clamped(toVisibleFrameOf: preferredScreen(for: frameRect))
    }

    /// Prefer the screen under the pointer so the panel can cross monitors;
    /// otherwise the screen with the largest intersection with the proposed frame.
    private static func preferredScreen(for frame: NSRect) -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let underMouse = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return underMouse
        }
        return NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
        }) ?? NSScreen.main
    }
}

private extension NSRect {
    /// Clamps origin so the full rect stays inside `screen.visibleFrame`.
    func clamped(toVisibleFrameOf screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return self }
        var frame = self
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        return frame
    }

    var area: CGFloat { max(0, width) * max(0, height) }
}

// Gentle scheduled reminders: defer Sparkle's auto alert and surface the rail Update button.
// User-initiated checks (menu / About / the button itself) still use Sparkle's standard UI.
extension AppDelegate: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            appState.pendingUpdateVersion = update.displayVersionString
            appState.updateAvailable = true
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        appState.pendingUpdateVersion = nil
        appState.updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        appState.pendingUpdateVersion = nil
        appState.updateAvailable = false
    }
}
