import SwiftUI
import AppKit
import OSLog

struct StoresTabView: View {
    @Environment(AppState.self) private var appState
    @State private var isAddingStore = false
    @State private var editingStore: Store?
    @State private var storePendingDeletion: Store?
    @State private var newDomain = ""
    @State private var newDisplayName = ""
    @State private var newColorHex = "1f6f4a"
    @State private var csvErrorMessage: String?
    @State private var isConfirmingDeleteAll = false
    @State private var draggingStoreID: Store.ID?
    @State private var isRefreshingFavicons = false
    @State private var faviconRefreshMessage: String?

    @State private var filter: StoreFilter = .all
    @State private var searchText = ""

    /// Which slice of the list the pane shows. `.new` only appears after a sync added stores.
    private enum StoreFilter: Hashable {
        case all
        case shown
        case hidden
        case new
    }

    var orderedStores: [Store] {
        appState.stores.sorted { $0.sortOrder < $1.sortOrder }
    }

    private enum Column {
        static let order: CGFloat = SettingsRowMetrics.reorderWidth
        static let accent: CGFloat = 20
        static let spacing: CGFloat = SettingsRowMetrics.rowSpacing
    }

    var body: some View {
        ScrollView {
            // Sorted once per body — `orderedStores` re-sorts on every access, and the
            // row loop below reads it for each row's drop delegate and last-row check.
            let ordered = orderedStores
            // The drop delegate gets the full order, not just the listed rows, so dragging
            // inside a filtered list lands next to the target in the real order.
            let orderedIDs = ordered.map(\.id)
            let newIDs = appState.recentlySyncedStoreIDs
            let listed = ordered.filter { matches($0, newIDs: newIDs) }

            VStack(alignment: .leading, spacing: 12) {
                shopifySyncCard

                if !ordered.isEmpty {
                    listToolbar(ordered: ordered, newIDs: newIDs)
                    listCaption(listed: listed, total: ordered.count)
                }

                VStack(spacing: 0) {
                    ForEach(listed) { store in
                        storeRow(store: store, isNew: newIDs.contains(store.id), isLast: store.id == listed.last?.id)
                            .onDrag {
                                draggingStoreID = store.id
                                return NSItemProvider(object: store.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ReorderDropDelegate(
                                    targetID: store.id,
                                    orderedIDs: orderedIDs,
                                    draggingID: $draggingStoreID,
                                    onMove: { from, to in
                                        reorderStores(from: from, to: to, save: false)
                                    },
                                    onDrop: {
                                        appState.saveStores()
                                    }
                                )
                            )
                    }

                    if listed.isEmpty {
                        emptyListRow(hasStores: !ordered.isEmpty)
                    }

                    SettingsGroupedDivider(leadingInset: listed.isEmpty ? SettingsRowMetrics.separatorLeading : SettingsRowMetrics.afterReorderSeparatorLeading)

                    HStack(spacing: 14) {
                        Button(action: beginAdding) {
                            HStack(spacing: Column.spacing) {
                                Image("PlusIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .frame(width: Column.order, alignment: .leading)
                                Text("Add Store")
                                    .font(.system(size: 12.5))
                            }
                            .foregroundStyle(Color.accentColor)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add a store by its myshopify.com domain")

                        Spacer(minLength: 0)

                        Button(action: refreshFavicons) {
                            HStack(spacing: 6) {
                                ZStack {
                                    if isRefreshingFavicons {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .frame(width: 14, height: 14)
                                Text(isRefreshingFavicons ? "Refreshing…" : "Refresh favicons")
                                    .font(.system(size: 12.5))
                            }
                            .foregroundStyle(Color.accentColor)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isRefreshingFavicons || appState.stores.isEmpty)
                    }
                    .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
                    .padding(.vertical, 9)
                }
                .settingsCardChrome()

                SettingsGroupedCard {
                    SettingsGroupedRow(
                        "Import & Export",
                        subtitle: "Backup or move your store list."
                    ) {
                        HStack(spacing: 14) {
                            SettingsTextLink("Import", action: importCSV)
                            SettingsTextLink("Export", action: exportCSV)
                            SettingsTextLink(
                                "Delete All",
                                isEnabled: !appState.stores.isEmpty,
                                isDestructive: true
                            ) {
                                isConfirmingDeleteAll = true
                            }
                        }
                    }
                }

                SettingsDocsFooter()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .settingsTopScrollEdgeBlur()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: appState.recentlySyncedStoreIDs.isEmpty) { _, isEmpty in
            if isEmpty, filter == .new { filter = .all }
        }
        // Coming back from Terminal (sign-in) or the browser (install guide): try again
        // without making the person find the button.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            switch appState.shopifySyncStatus {
            case .needsSignIn, .notInstalled:
                appState.syncShopifyStores()
            default:
                break
            }
        }
        .sheet(isPresented: $isAddingStore) {
            storeSheet(title: "Add a store", confirmTitle: "Add", store: nil, domain: $newDomain, displayName: $newDisplayName, colorBinding: newColorBinding) {
                addStore()
            } onCancel: {
                isAddingStore = false
            }
        }
        .sheet(item: $editingStore) { store in
            storeSheet(title: "Edit store", confirmTitle: "Save", store: store, domain: $newDomain, displayName: $newDisplayName, colorBinding: colorBinding(for: store)) {
                saveEdits(to: store)
            } onCancel: {
                editingStore = nil
            }
        }
        .deleteConfirmation(pendingStore: $storePendingDeletion, appState: appState, editingStore: $editingStore)
        .confirmationDialog(
            "Delete all \(appState.stores.count) stores?",
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { deleteAllStores() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Export a CSV first if you want to restore this list later.")
        }
        .csvErrorAlert($csvErrorMessage)
        .alert("Favicons", isPresented: Binding(
            get: { faviconRefreshMessage != nil },
            set: { if !$0 { faviconRefreshMessage = nil } }
        )) {
            Button("OK", role: .cancel) { faviconRefreshMessage = nil }
        } message: {
            Text(faviconRefreshMessage ?? "")
        }
    }

    // MARK: - Shopify sync

    private var shopifySyncCard: some View {
        SettingsGroupedCard {
            HStack(alignment: .center, spacing: 12) {
                Image("ShopifyIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textPrimary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sync from Shopify")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textPrimary)
                    Text(syncSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                syncPrimaryAction
            }
            .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
            .padding(.vertical, 10)

            syncNotice
        }
    }

    private var syncSubtitle: String {
        if appState.isSyncingShopify {
            return "Checking your Shopify organizations…"
        }
        guard let record = appState.lastShopifySync else {
            return "Adds every store your Shopify organizations can reach. You can still hide and reorder them."
        }
        let when = record.date.formatted(.relative(presentation: .named))
        let stores = record.storeCount == 1 ? "1 store" : "\(record.storeCount) stores"
        guard !record.organizationNames.isEmpty else {
            return "Last synced \(when) · \(stores)"
        }
        return "Last synced \(when) · \(stores) in \(record.organizationNames.formatted(.list(type: .and)))"
    }

    @ViewBuilder
    private var syncPrimaryAction: some View {
        switch appState.shopifySyncStatus {
        case .syncing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .needsSignIn:
            Button("Sign In…", action: signInToShopify)
                .controlSize(.small)
        case .notInstalled:
            Button("Install Guide") { NSWorkspace.shared.open(ShopifyCLI.installGuideURL) }
                .controlSize(.small)
        default:
            Button("Sync Now") { appState.syncShopifyStores() }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var syncNotice: some View {
        switch appState.shopifySyncStatus {
        case .synced(let summary):
            let addedCount = appState.recentlySyncedStoreIDs.count
            let hiddenCount = appState.stores.filter { appState.recentlySyncedStoreIDs.contains($0.id) && !$0.isVisible }.count
            noticeRow(
                symbol: "checkmark.circle.fill",
                tint: .green,
                message: syncResultMessage(added: addedCount, hidden: hiddenCount, matched: summary.matchedCount)
            ) {
                if addedCount > 0 {
                    SettingsTextLink("Review") {
                        searchText = ""
                        filter = .new
                    }
                }
                SettingsTextLink("Done") { appState.dismissShopifySyncSummary() }
            }
        case .needsSignIn:
            noticeRow(
                symbol: "person.crop.circle.badge.exclamationmark",
                tint: .orange,
                message: "Shopify needs you to sign in again. Click Sign In to open Terminal. If your account is already listed, choose ‘Log in with a different account’ and sign in with the same account to renew the session. Return here to sync automatically."
            ) {
                SettingsTextLink("Try Again") { appState.syncShopifyStores() }
            }
        case .notInstalled:
            noticeRow(
                symbol: "terminal",
                tint: .orange,
                message: "Storefront reads your stores through the Shopify CLI. Install it with `npm install -g @shopify/cli@latest` (or Homebrew), then sync again."
            ) {
                SettingsTextLink("Try Again") { appState.syncShopifyStores() }
            }
        case .failed(let message):
            noticeRow(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                message: "Sync didn't finish: \(message)"
            ) {
                SettingsTextLink("Try Again") { appState.syncShopifyStores() }
            }
        case .idle, .syncing:
            EmptyView()
        }
    }

    private func syncResultMessage(added: Int, hidden: Int, matched: Int) -> String {
        guard added > 0 else {
            return matched == 0
                ? "Shopify didn't list any stores for this account."
                : "You're up to date. All \(matched) stores from Shopify are already here."
        }
        let addedText = added == 1 ? "Added 1 store" : "Added \(added) stores"
        switch hidden {
        case 0: return "\(addedText) to your panel."
        case added: return "\(addedText). They start hidden, so turn on the ones you want in the panel."
        default: return "\(addedText). \(hidden) of them are hidden until you turn them on."
        }
    }

    private func noticeRow<Actions: View>(
        symbol: String,
        tint: Color,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            SettingsGroupedDivider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(Self.inlineMarkdown(message))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    actions()
                }
            }
            .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
            .padding(.vertical, 9)
        }
    }

    private static func inlineMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private func signInToShopify() {
        Task {
            do {
                try await ShopifyCLI.openSignInInTerminal()
            } catch ShopifyCLI.Failure.notInstalled {
                appState.shopifySyncStatus = .notInstalled
            } catch {
                appState.shopifySyncStatus = .failed("Couldn't open Terminal: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Filtering

    private func matches(_ store: Store, newIDs: Set<Store.ID>) -> Bool {
        switch filter {
        case .all: break
        case .shown: guard store.isVisible else { return false }
        case .hidden: guard !store.isVisible else { return false }
        case .new: guard newIDs.isEmpty || newIDs.contains(store.id) else { return false }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return store.matchesSearchQuery(query) || store.myshopifyDomain.localizedCaseInsensitiveContains(query)
    }

    private var isFiltering: Bool {
        filter != .all || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func listToolbar(ordered: [Store], newIDs: Set<Store.ID>) -> some View {
        let shownCount = ordered.filter(\.isVisible).count
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textMeta40)
                TextField("Filter by name or domain", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMeta40)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.settingsCardFill)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.borderColor, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)

            Picker("Show", selection: $filter) {
                Text("All \(ordered.count)").tag(StoreFilter.all)
                Text("Shown \(shownCount)").tag(StoreFilter.shown)
                Text("Hidden \(ordered.count - shownCount)").tag(StoreFilter.hidden)
                if !newIDs.isEmpty {
                    Text("New \(newIDs.count)").tag(StoreFilter.new)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func listCaption(listed: [Store], total: Int) -> some View {
        let allListedVisible = listed.allSatisfy(\.isVisible)
        let actionTitle: String = {
            let verb = allListedVisible ? "Hide" : "Show"
            return isFiltering ? "\(verb) \(listed.count)" : "\(verb) All"
        }()
        return HStack {
            Text(isFiltering
                 ? "Showing \(listed.count) of \(total) stores. Drag to reorder."
                 : "Drag rows to reorder. Hidden stores stay out of the panel.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if !listed.isEmpty {
                Button(actionTitle) { setVisibility(!allListedVisible, for: listed) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func emptyListRow(hasStores: Bool) -> some View {
        HStack(spacing: 8) {
            Text(hasStores
                 ? "No stores match."
                 : "No stores yet. Sync from Shopify above, or add one by its domain.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if hasStores {
                SettingsTextLink("Clear Filter") {
                    searchText = ""
                    filter = .all
                }
            }
        }
        .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
        .padding(.vertical, 12)
    }

    /// One save for the whole batch. Hiding the selected store hands the selection to the
    /// first visible one, the same as hiding it from its row.
    private func setVisibility(_ visible: Bool, for listed: [Store]) {
        let ids = Set(listed.map(\.id))
        for index in appState.stores.indices where ids.contains(appState.stores[index].id) {
            appState.stores[index].isVisible = visible
        }
        if appState.selectedStore.map({ !$0.isVisible }) ?? true {
            appState.selectedStoreID = appState.visibleStores.first?.id
        }
        appState.saveStores()
    }

    private func storeRow(store: Store, isNew: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Column.spacing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMeta25)
                    .frame(width: Column.order, alignment: .leading)

                colorSwatch(color: colorBinding(for: store))
                    .frame(width: Column.accent, alignment: .leading)
                    .opacity(store.isVisible ? 1 : 0.5)

                StoreFaviconView(store: store, size: 18)
                    .opacity(store.isVisible ? 1 : 0.5)

                Text(store.displayName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .opacity(store.isVisible ? 1 : 0.5)
                    .help(store.myshopifyDomain)

                if isNew {
                    Text("New")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }

                Spacer(minLength: 12)

                Button {
                    appState.togglePinned(store)
                } label: {
                    Image(store.isPinned ? "PinFilledIcon" : "PinIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.isPinned ? Theme.textPrimary : Theme.textMeta40)

                Button {
                    beginEditing(store)
                } label: {
                    Image("EditIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMeta40)

                Button {
                    storePendingDeletion = store
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMeta40)

                Toggle("", isOn: visibilityBinding(for: store))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
            .padding(.vertical, 9)
            .opacity(draggingStoreID == store.id ? 0.45 : 1)

            if !isLast {
                SettingsGroupedDivider(leadingInset: SettingsRowMetrics.afterReorderSeparatorLeading)
            }
        }
    }

    private func visibilityBinding(for store: Store) -> Binding<Bool> {
        Binding(
            get: { store.isVisible },
            set: { appState.setStoreVisible(store, $0) }
        )
    }

    private func colorSwatch(color: Binding<Color>) -> some View {
        // ColorPicker always draws a rounded-rect well with its own chrome. Clipping that
        // rect to a circle leaves the well's top/bottom edges as flat grey chords —
        // scale the control up so those edges fall outside the mask.
        ColorPicker("", selection: color, supportsOpacity: false)
            .labelsHidden()
            .scaleEffect(1.8)
            .frame(width: 20, height: 20)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.borderColor, lineWidth: 1))
            .contentShape(Circle())
    }

    private func deleteAllStores() {
        appState.removeAllStores()
    }

    private func refreshFavicons() {
        guard !isRefreshingFavicons else { return }
        isRefreshingFavicons = true
        Task {
            let updated = await appState.refreshFavicons()
            isRefreshingFavicons = false
            if updated == 0 {
                faviconRefreshMessage = "Couldn't find new favicons. Stores without a public icon keep their initials."
            } else {
                faviconRefreshMessage = updated == 1
                    ? "Updated 1 favicon."
                    : "Updated \(updated) favicons."
            }
        }
    }

    private func reorderStores(from: Int, to: Int, save: Bool) {
        var ordered = orderedStores
        ordered.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        for (index, store) in ordered.enumerated() {
            guard let idx = appState.stores.firstIndex(where: { $0.id == store.id }) else { continue }
            appState.stores[idx].sortOrder = index
        }
        if save {
            appState.saveStores()
        }
    }

    private func colorBinding(for store: Store) -> Binding<Color> {
        Binding(
            get: { store.color },
            set: { newColor in
                guard let index = appState.stores.firstIndex(where: { $0.id == store.id }) else { return }
                appState.stores[index].colorHex = newColor.hexString
                // NSColorPanel fires continuously while the wheel is dragged.
                appState.scheduleSaveStores()
            }
        )
    }

    private func beginEditing(_ store: Store) {
        newDisplayName = store.displayName
        newDomain = store.myshopifyDomain
        editingStore = store
    }

    private func beginAdding() {
        newColorHex = Store.defaultColorHex(forIndex: appState.stores.count)
        isAddingStore = true
    }

    private var newColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: newColorHex) },
            set: { newColorHex = $0.hexString }
        )
    }

    private func storeSheet(
        title: String,
        confirmTitle: String,
        store: Store?,
        domain: Binding<String>,
        displayName: Binding<String>,
        colorBinding: Binding<Color>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Store URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("mystore.myshopify.com", text: domain)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Display name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Display name", text: displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    colorSwatch(color: colorBinding)
                    Text("Click the swatch to change it")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack {
                if let store {
                    Button("Delete…", role: .destructive) {
                        storePendingDeletion = store
                    }
                }
                Spacer()
                Button("Cancel", action: onCancel)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(domain.wrappedValue.isEmpty || displayName.wrappedValue.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        // Attached here too (not just on the outer body): a `.confirmationDialog`
        // can only present over whichever presentation layer it's attached to, and
        // while this sheet is up, the outer body's copy is behind it and can't
        // surface until the sheet dismisses.
        .deleteConfirmation(pendingStore: $storePendingDeletion, appState: appState, editingStore: $editingStore)
    }

    private func addStore() {
        let domain = Store.normalizedDomain(newDomain)
        appState.addStore(domain: domain, displayName: newDisplayName, colorHex: newColorHex)
        newDomain = ""
        newDisplayName = ""
        isAddingStore = false
    }

    private func saveEdits(to store: Store) {
        let domain = Store.normalizedDomain(newDomain)
        appState.updateStore(store, displayName: newDisplayName, domain: domain)
        editingStore = nil
    }

    // MARK: - CSV import/export

    private func exportCSV() {
        guard let url = CSVFilePanel.exportURL(defaultName: "storefront-stores.csv") else { return }
        do {
            try appState.storesCSV().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            settingsCSVLogger.error("CSV export failed: \(error.localizedDescription, privacy: .public)")
            csvErrorMessage = "Couldn't save the CSV file: \(error.localizedDescription)"
        }
    }

    private func importCSV() {
        guard let url = CSVFilePanel.importURL() else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            appState.importStoresCSV(contents)
        } catch {
            settingsCSVLogger.error("CSV import failed: \(error.localizedDescription, privacy: .public)")
            csvErrorMessage = "Couldn't read that file — make sure it's a valid UTF-8 CSV."
        }
    }
}

private extension View {
    /// Applied at both the outer Stores list and inside the edit sheet, since a
    /// `.confirmationDialog` only presents over the layer it's attached to.
    func deleteConfirmation(pendingStore: Binding<Store?>, appState: AppState, editingStore: Binding<Store?>) -> some View {
        confirmationDialog(
            "Remove \(pendingStore.wrappedValue?.displayName ?? "this store")?",
            isPresented: Binding(
                get: { pendingStore.wrappedValue != nil },
                set: { if !$0 { pendingStore.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let store = pendingStore.wrappedValue {
                    appState.removeStore(store)
                }
                pendingStore.wrappedValue = nil
                editingStore.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                pendingStore.wrappedValue = nil
            }
        } message: {
            Text("This removes it from Storefront only. Your Shopify store itself isn't affected.")
        }
    }
}
