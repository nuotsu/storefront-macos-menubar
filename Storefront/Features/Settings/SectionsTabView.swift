import SwiftUI
import AppKit
import OSLog

/// One global list — enable/disable and reorder apply to every store. (An earlier version
/// let toggles override individual stores via a picker, but that only ever visibly
/// affected whichever store happened to be selected, which read as broken.)
///
/// Uses `ScrollView` (not `List`) so Tahoe’s titleband scroll-edge doesn’t collapse the
/// Settings `NavigationSplitView` under the traffic lights.
struct SectionsTabView: View {
    @Environment(AppState.self) private var appState
    @State private var csvErrorMessage: String?

    @State private var isPresentingSaveSheet = false
    @State private var isPresentingRenameSheet = false
    @State private var presetNameDraft = ""
    @State private var isConfirmingOverwrite = false
    @State private var isConfirmingDelete = false
    @State private var pendingOverwriteName = ""
    @State private var draggingSection: SectionID?

    private var allEnabled: Bool {
        appState.settings.enabledSections.count == SectionID.allCases.count
    }

    private var activePreset: ActiveSectionPreset {
        // Explicit Custom selection sticks even when the layout still matches a named preset.
        if appState.settings.prefersCustomSectionPreset {
            return .custom
        }
        // Sticky saved selection when that layout also matches a built-in.
        if let id = appState.settings.preferredSavedSectionPresetID,
           let saved = appState.settings.savedSectionPresets.first(where: { $0.id == id }),
           saved.sectionOrder == appState.settings.sectionOrder,
           saved.enabledSections == appState.settings.enabledSections {
            return .saved(id)
        }
        return ActiveSectionPreset.match(
            order: appState.settings.sectionOrder,
            enabled: appState.settings.enabledSections,
            saved: appState.settings.savedSectionPresets
        )
    }

    private var selectedSavedPreset: SavedSectionPreset? {
        guard case .saved(let id) = activePreset else { return nil }
        return appState.settings.savedSectionPresets.first { $0.id == id }
    }

    private var presetBinding: Binding<ActiveSectionPreset> {
        Binding(
            get: { activePreset },
            set: { selection in
                switch selection {
                case .builtin(let preset):
                    let layout = preset.layout()
                    appState.settings.prefersCustomSectionPreset = false
                    appState.settings.preferredSavedSectionPresetID = nil
                    appState.settings.sectionOrder = layout.order
                    appState.settings.enabledSections = layout.enabled
                    appState.saveSettings()
                case .saved(let id):
                    guard let saved = appState.settings.savedSectionPresets.first(where: { $0.id == id }) else { return }
                    appState.settings.prefersCustomSectionPreset = false
                    appState.settings.preferredSavedSectionPresetID = id
                    appState.settings.sectionOrder = saved.sectionOrder
                    appState.settings.enabledSections = saved.enabledSections
                    appState.saveSettings()
                case .custom:
                    appState.settings.prefersCustomSectionPreset = true
                    appState.settings.preferredSavedSectionPresetID = nil
                    appState.saveSettings()
                }
            }
        )
    }

    private func toggleAllEnabled() {
        appState.settings.enabledSections = allEnabled ? [] : Set(SectionID.allCases)
        appState.saveSettings()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroupedCard {
                    SettingsGroupedRow(
                        "Preset",
                        subtitle: "Choose a role-based layout, or save your own custom arrangement."
                    ) {
                        Picker("", selection: presetBinding) {
                            ForEach(SectionPreset.allCases) { preset in
                                Text(preset.title).tag(ActiveSectionPreset.builtin(preset))
                            }
                            Section("Custom") {
                                ForEach(appState.settings.savedSectionPresets) { preset in
                                    Text(preset.name).tag(ActiveSectionPreset.saved(preset.id))
                                }
                                Text("Create new").tag(ActiveSectionPreset.custom)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow(
                        "Custom",
                        subtitle: "Save the current section layout as a named preset."
                    ) {
                        HStack(spacing: 14) {
                            SettingsTextLink(
                                "Save current",
                                isEnabled: activePreset == .custom
                            ) {
                                presetNameDraft = ""
                                isPresentingSaveSheet = true
                            }
                            if selectedSavedPreset != nil {
                                SettingsTextLink("Rename") {
                                    presetNameDraft = selectedSavedPreset?.name ?? ""
                                    isPresentingRenameSheet = true
                                }
                                SettingsTextLink("Delete", isDestructive: true) {
                                    isConfirmingDelete = true
                                }
                            }
                        }
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow(
                        "Library",
                        subtitle: "Manage your saved custom presets as CSV."
                    ) {
                        HStack(spacing: 14) {
                            SettingsTextLink("Import", action: importPresetsCSV)
                            SettingsTextLink(
                                "Export",
                                isEnabled: !appState.settings.savedSectionPresets.isEmpty,
                                action: exportPresetsCSV
                            )
                        }
                    }
                }

                HStack {
                    Text("Applies to every store. Drag rows to reorder.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    Button(allEnabled ? "Disable All" : "Enable All", action: toggleAllEnabled)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 0) {
                    ForEach(appState.settings.sectionOrder, id: \.self) { section in
                        sectionRow(section)
                            .onDrag {
                                draggingSection = section
                                return NSItemProvider(object: section.rawValue as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ReorderDropDelegate(
                                    targetID: section,
                                    orderedIDs: appState.settings.sectionOrder,
                                    draggingID: $draggingSection,
                                    onMove: { from, to in
                                        appState.settings.sectionOrder.move(
                                            fromOffsets: IndexSet(integer: from),
                                            toOffset: to
                                        )
                                    },
                                    onDrop: { appState.saveSettings() }
                                )
                            )
                    }
                }
                .settingsCardChrome()

                SettingsDocsFooter()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .settingsTopScrollEdgeBlur()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPresentingSaveSheet) {
            presetNameSheet(
                title: "Save Preset",
                confirmTitle: "Save",
                onConfirm: { attemptSavePreset(named: $0) },
                onCancel: { isPresentingSaveSheet = false }
            )
        }
        .sheet(isPresented: $isPresentingRenameSheet) {
            presetNameSheet(
                title: "Rename Preset",
                confirmTitle: "Rename",
                onConfirm: { attemptRenamePreset(to: $0) },
                onCancel: { isPresentingRenameSheet = false }
            )
        }
        .confirmationDialog(
            "Overwrite preset?",
            isPresented: $isConfirmingOverwrite,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) {
                commitSavePreset(named: pendingOverwriteName, overwrite: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A preset named “\(pendingOverwriteName)” already exists. Replace its layout with the current sections?")
        }
        .confirmationDialog(
            "Delete preset?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedSavedPreset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let name = selectedSavedPreset?.name {
                Text("Remove “\(name)” from saved presets? Your current section layout is unchanged.")
            } else {
                Text("Remove this saved preset? Your current section layout is unchanged.")
            }
        }
        .csvErrorAlert($csvErrorMessage)
    }

    private func sectionRow(_ section: SectionID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsRowMetrics.rowSpacing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMeta25)
                    .frame(width: SettingsRowMetrics.reorderWidth, alignment: .leading)
                Image(section.iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textMeta40)
                Text(section.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("", isOn: bindingFor(section: section))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
            .padding(.vertical, 9)
            .opacity(draggingSection == section ? 0.45 : 1)

            if section != appState.settings.sectionOrder.last {
                SettingsGroupedDivider(leadingInset: SettingsRowMetrics.afterReorderSeparatorLeading)
            }
        }
        .background(Theme.settingsCardFill)
    }

    private func presetNameSheet(
        title: String,
        confirmTitle: String,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Preset name", text: $presetNameDraft)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    onConfirm(presetNameDraft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func attemptSavePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let lowered = name.lowercased()
        if appState.settings.savedSectionPresets.contains(where: { $0.name.lowercased() == lowered }) {
            pendingOverwriteName = name
            isPresentingSaveSheet = false
            isConfirmingOverwrite = true
            return
        }
        commitSavePreset(named: name, overwrite: false)
        isPresentingSaveSheet = false
    }

    private func commitSavePreset(named name: String, overwrite: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let order = appState.settings.sectionOrder
        let enabled = appState.settings.enabledSections
        let lowered = trimmed.lowercased()

        let savedID: UUID
        if let index = appState.settings.savedSectionPresets.firstIndex(where: { $0.name.lowercased() == lowered }) {
            guard overwrite else { return }
            appState.settings.savedSectionPresets[index].name = trimmed
            appState.settings.savedSectionPresets[index].sectionOrder = order
            appState.settings.savedSectionPresets[index].enabledSections = enabled
            savedID = appState.settings.savedSectionPresets[index].id
        } else {
            let preset = SavedSectionPreset(name: trimmed, sectionOrder: order, enabledSections: enabled)
            appState.settings.savedSectionPresets.append(preset)
            savedID = preset.id
        }
        // Prefer the saved preset even when its layout also matches a built-in.
        appState.settings.prefersCustomSectionPreset = false
        appState.settings.preferredSavedSectionPresetID = savedID
        appState.saveSettings()
    }

    private func attemptRenamePreset(to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let selected = selectedSavedPreset else { return }
        let lowered = name.lowercased()
        if let conflict = appState.settings.savedSectionPresets.first(where: {
            $0.id != selected.id && $0.name.lowercased() == lowered
        }) {
            csvErrorMessage = "A preset named “\(conflict.name)” already exists."
            return
        }
        guard let index = appState.settings.savedSectionPresets.firstIndex(where: { $0.id == selected.id }) else { return }
        appState.settings.savedSectionPresets[index].name = name
        appState.saveSettings()
        isPresentingRenameSheet = false
    }

    private func deleteSelectedSavedPreset() {
        guard let selected = selectedSavedPreset else { return }
        appState.settings.savedSectionPresets.removeAll { $0.id == selected.id }
        if appState.settings.preferredSavedSectionPresetID == selected.id {
            appState.settings.preferredSavedSectionPresetID = nil
        }
        appState.saveSettings()
    }

    private func bindingFor(section: SectionID) -> Binding<Bool> {
        Binding(
            get: { appState.settings.enabledSections.contains(section) },
            set: { newValue in
                if newValue {
                    appState.settings.enabledSections.insert(section)
                } else {
                    appState.settings.enabledSections.remove(section)
                }
                appState.saveSettings()
            }
        )
    }

    // MARK: - Preset library CSV

    private func exportPresetsCSV() {
        guard let url = CSVFilePanel.exportURL(defaultName: "storefront-section-presets.csv") else { return }
        do {
            try appState.sectionPresetsCSV().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            settingsCSVLogger.error("Presets CSV export failed: \(error.localizedDescription, privacy: .public)")
            csvErrorMessage = "Couldn't save the presets CSV: \(error.localizedDescription)"
        }
    }

    private func importPresetsCSV() {
        guard let url = CSVFilePanel.importURL() else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let upserted = appState.importSectionPresetsCSV(contents)
            if upserted == 0 {
                csvErrorMessage = "No presets found in that file. Expected a CSV with Preset, Section, and Enabled columns."
            }
        } catch {
            settingsCSVLogger.error("Presets CSV import failed: \(error.localizedDescription, privacy: .public)")
            csvErrorMessage = "Couldn't read that file — make sure it's a valid UTF-8 CSV."
        }
    }
}
