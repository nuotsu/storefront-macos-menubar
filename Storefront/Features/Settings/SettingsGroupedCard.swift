import SwiftUI

/// Shared metrics for Settings list/card rows (aligned with Keybindings).
enum SettingsRowMetrics {
    static let horizontalPadding: CGFloat = 11
    static let reorderWidth: CGFloat = 22
    static let rowSpacing: CGFloat = 6
    /// Subtle left cutoff for inter-row hairlines (Keybindings / non-reorder rows).
    static let separatorLeading: CGFloat = 11
    /// Hairline starts after the reorder grip + gap (not underneath the handle).
    static var afterReorderSeparatorLeading: CGFloat {
        horizontalPadding + reorderWidth + rowSpacing
    }
}

/// Hairline between grouped rows — inset on the leading edge like Keybindings.
struct SettingsGroupedDivider: View {
    var leadingInset: CGFloat = SettingsRowMetrics.separatorLeading

    var body: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.leading, leadingInset)
    }
}

extension View {
    /// The Settings card surface: fill, rounded clip, hairline border. Four panes had
    /// this same trio inlined — two of them with a non-continuous corner curve, which
    /// this normalizes.
    func settingsCardChrome() -> some View {
        self
            .background(Theme.settingsCardFill)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.borderColor, lineWidth: 1)
            )
    }
}

/// Full-width bordered group for settings rows (cmux-style card chrome).
struct SettingsGroupedCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .settingsCardChrome()
    }
}

/// One full-width row: title (+ optional subtitle) on the left, control on the right.
struct SettingsGroupedRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    var alignment: VerticalAlignment
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        alignment: VerticalAlignment = .center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.alignment = alignment
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 3) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(Self.attributedSubtitle(subtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .tint(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
        .padding(.vertical, 9)
    }

    private static func attributedSubtitle(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(string)
    }
}

/// Footer subtext linking to the public docs — use at the bottom of each Settings pane.
struct SettingsDocsFooter: View {
    var body: some View {
        Text(Self.attributedLabel)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .tint(Color.accentColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    /// `let`, not a computed `var`: every Settings pane draws this footer, and a
    /// computed property re-parsed the Markdown on each body evaluation.
    private static let attributedLabel: AttributedString = {
        (try? AttributedString(
            markdown: "Learn more in the [docs](https://storefront.nuotsu.dev/docs).",
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString("Learn more in the docs.")
    }()
}

/// Plain text action link for Settings footers — no pill chrome.
struct SettingsTextLink: View {
    let title: String
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.action = action
    }

    private var textColor: Color {
        guard isEnabled else { return Theme.textMeta40 }
        return isDestructive ? .red : Color.accentColor
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(textColor)
            .disabled(!isEnabled)
    }
}

extension View {
    /// Soft progressive blur under the Settings titleband (Tahoe+). No-op below macOS 26.
    @ViewBuilder
    func settingsTopScrollEdgeBlur() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Pins a top bar that participates in the system scroll-edge progressive blur
    /// (`safeAreaBar` on macOS 26+). Falls back to `safeAreaInset` below Tahoe.
    @ViewBuilder
    func detailHeaderSafeAreaBar<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: .top, spacing: 0) {
                bar()
            }
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) {
                bar()
            }
        }
    }
}

// MARK: - Shared drag-reorder

/// Drag-reorder drop delegate for the Settings list rows. The Stores and Sections panes
/// each carried their own copy, identical down to the `to > from ? to + 1 : to` fixup.
struct ReorderDropDelegate<ID: Hashable>: DropDelegate {
    let targetID: ID
    let orderedIDs: [ID]
    @Binding var draggingID: ID?
    /// Receives the destination index with the drag-past-self fixup already applied.
    let onMove: (_ from: Int, _ to: Int) -> Void
    let onDrop: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let from = orderedIDs.firstIndex(of: draggingID),
              let to = orderedIDs.firstIndex(of: targetID)
        else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            onMove(from, to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onDrop()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Shortcut badges

/// Fill behind a shortcut badge. Keybindings tints against the card; How to use sits on
/// a lighter surface and needs more contrast — the only thing that ever differed between
/// the two panes' otherwise identical badge code.
enum SettingsBadgeFill {
    static let onCard = Color.adaptive(light: .black.opacity(0.06), dark: .white.opacity(0.06))
    static let onSurface = Color.adaptive(light: .white, dark: .white.opacity(0.12))
}

private struct SettingsBadgeChrome: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.textMeta40)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderColor.opacity(0.7), lineWidth: 1))
    }
}

/// A key combo rendered as a keycap chip.
struct SettingsKeyBadge: View {
    let combo: KeyCombo
    var fill: Color = SettingsBadgeFill.onCard

    var body: some View {
        KeyComboView(combo: combo, font: .system(size: 11, weight: .medium), glyphHeight: 12)
            .modifier(SettingsBadgeChrome(fill: fill))
    }
}

/// A plain-text chip matching `SettingsKeyBadge` (e.g. "Click", "Drag").
struct SettingsTextBadge: View {
    let label: String
    var fill: Color = SettingsBadgeFill.onCard

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .frame(height: 12)
            .modifier(SettingsBadgeChrome(fill: fill))
    }
}
