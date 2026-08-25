import SwiftUI

struct GeneralTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroupedCard {
                    SettingsGroupedRow("Launch at login") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { appState.settings.launchAtLogin },
                                set: { appState.setLaunchAtLogin($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow("Show in Dock") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { appState.settings.showInDock },
                                set: { AppDelegate.shared?.setShowInDock($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow("Show in menu bar") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { appState.settings.showInMenuBar },
                                set: { AppDelegate.shared?.setShowInMenuBar($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow("Favorited stores in menu bar") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { appState.settings.showStarredStoresInMenuBar },
                                set: { appState.setShowStarredStoresInMenuBar($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.settings.showInMenuBar)
                    }

                    SettingsGroupedDivider()

                    SettingsGroupedRow(
                        "Open under mouse",
                        subtitle: "Disable to open below the menu bar icon."
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { appState.settings.openUnderMouse },
                                set: { appState.setOpenUnderMouse($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.settings.showInMenuBar)
                    }
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
