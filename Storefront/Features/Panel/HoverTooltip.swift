import SwiftUI

/// Shared presenter so tooltips draw in a root overlay (above rail/cards) instead of
/// being clipped by local containers.
@Observable
@MainActor
final class HoverTooltipController {
    static let coordinateSpaceName = "hoverTooltipContainer"
    /// Inset from the container edge when clamping a tooltip that would otherwise clip.
    static let edgeMargin: CGFloat = 8
    /// Gap between the hovered control and the tooltip above it.
    static let anchorGap: CGFloat = 3
    /// Brief window after leaving a target where a neighbor can claim the bubble
    /// without a hide + re-delay.
    static let dismissGrace: Duration = .milliseconds(100)

    /// Where on the hover target the tooltip sits above.
    enum VerticalAnchor: Equatable {
        /// Above the top edge — default for compact controls.
        case top
        /// Above the vertical center — better for tall hit targets (e.g. row-height pills).
        case center
    }

    struct Presentation: Equatable {
        let token: UUID
        let text: String
        let shortcut: KeyCombo?
        var anchor: CGRect
        var gap: CGFloat
        var verticalAnchor: VerticalAnchor
        /// When set, Y is keyed off this rect’s top (e.g. store row) while X follows `anchor`.
        var verticalBand: CGRect?
    }

    private(set) var presentation: Presentation?
    private var dismissTask: Task<Void, Never>?

    /// True while a tooltip bubble is on screen (including during dismiss grace).
    var isShowing: Bool { presentation != nil }

    func present(
        token: UUID,
        text: String,
        shortcut: KeyCombo?,
        anchor: CGRect,
        gap: CGFloat = anchorGap,
        verticalAnchor: VerticalAnchor = .top,
        verticalBand: CGRect? = nil
    ) {
        dismissTask?.cancel()
        dismissTask = nil
        presentation = Presentation(
            token: token,
            text: text,
            shortcut: shortcut,
            anchor: anchor,
            gap: gap,
            verticalAnchor: verticalAnchor,
            verticalBand: verticalBand
        )
    }

    func updateAnchor(token: UUID, anchor: CGRect, verticalBand: CGRect? = nil) {
        guard presentation?.token == token else { return }
        presentation?.anchor = anchor
        if let verticalBand {
            presentation?.verticalBand = verticalBand
        }
    }

    /// Clears immediately when `token` still owns the presentation.
    func dismiss(token: UUID) {
        guard presentation?.token == token else { return }
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
    }

    /// Delays clear so a neighboring target can present and keep the bubble alive.
    func scheduleDismiss(token: UUID, after: Duration = dismissGrace) {
        guard presentation?.token == token else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: after)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard presentation?.token == token else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                presentation = nil
            }
        }
    }

    /// Top-leading origin for a tooltip that prefers sitting above `anchor`, clamped
    /// into `container` with `edgeMargin` so the full bubble stays on-screen.
    static func clampedOrigin(
        anchor: CGRect,
        tooltipSize: CGSize,
        container: CGSize,
        margin: CGFloat = edgeMargin,
        gap: CGFloat = anchorGap,
        verticalAnchor: VerticalAnchor = .top,
        verticalBand: CGRect? = nil
    ) -> CGPoint {
        guard tooltipSize.width > 0, tooltipSize.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }

        let anchorY: CGFloat
        if let verticalBand {
            anchorY = verticalBand.minY
        } else {
            switch verticalAnchor {
            case .top: anchorY = anchor.minY
            case .center: anchorY = anchor.midY
            }
        }

        var x = anchor.midX - tooltipSize.width / 2
        var y = anchorY - gap - tooltipSize.height

        let maxX = max(margin, container.width - tooltipSize.width - margin)
        let maxY = max(margin, container.height - tooltipSize.height - margin)
        x = min(max(margin, x), maxX)
        y = min(max(margin, y), maxY)
        return CGPoint(x: x, y: y)
    }
}

private struct HoverTooltipControllerKey: EnvironmentKey {
    static var defaultValue: HoverTooltipController? { nil }
}

extension EnvironmentValues {
    var hoverTooltipController: HoverTooltipController? {
        get { self[HoverTooltipControllerKey.self] }
        set { self[HoverTooltipControllerKey.self] = newValue }
    }
}

// MARK: - Bubble

struct HoverTooltipBubble: View {
    let text: String
    var shortcut: KeyCombo? = nil
    var isShopify: Bool = false

    var body: some View {
        if isShopify {
            shopifyBody
        } else {
            macOSBody
        }
    }

    /// Admin tooltip popover: `#0a0a0a`, 10px radius,
    /// `rgba(220,220,220,.18) 0 0 0 1px, rgba(0,0,0,.15) 0 1px 2px, rgba(0,0,0,.15) 0 3px 6px -5px,
    /// rgba(0,0,0,.84) 0 8px 24px -8px`, one gray keycap per key.
    private var shopifyBody: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .circular)
        return HStack(spacing: 8) {
            Text(text)
                .font(.panel(11.5, shopify: true))
                .foregroundStyle(Theme.Shopify.Sidebar.textItem)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let shortcut {
                HStack(spacing: 3) {
                    ForEach(shortcut.modifierSymbolNames, id: \.self) { name in
                        shopifyKeycap { Image(systemName: name) }
                    }
                    switch shortcut.keyGlyph {
                    case .symbol(let name):
                        shopifyKeycap { Image(systemName: name) }
                    case .text(let text):
                        shopifyKeycap { Text(text) }
                    }
                }
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, shortcut == nil ? 9 : 5)
        .padding(.vertical, 5)
        .background {
            shape
                .fill(Theme.Shopify.Sidebar.fill)
                .overlay { shape.strokeBorder(Color(white: 220 / 255).opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.84), radius: 8, y: 6)
        }
    }

    private func shopifyKeycap<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.panel(9, weight: .medium, shopify: true))
            .foregroundStyle(Theme.Shopify.Sidebar.textItem)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 1)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .circular)
                    .fill(Color.white.opacity(0.14))
            }
    }

    private var macOSBody: some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.panel(11, shopify: isShopify))
                .foregroundStyle(isShopify ? Theme.Shopify.textPrimary : Theme.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let shortcut {
                KeyComboView(
                    combo: shortcut,
                    font: .panel(8, weight: .medium, shopify: isShopify),
                    glyphHeight: 9
                )
                .foregroundStyle(isShopify ? Theme.Shopify.textSecondary : Theme.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: isShopify ? 4 : 3, style: isShopify ? .circular : .continuous)
                        .strokeBorder(
                            isShopify ? Theme.Shopify.border : Theme.borderColor,
                            lineWidth: 1
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: isShopify ? 8 : 6, style: isShopify ? .circular : .continuous)
                .fill(isShopify ? Theme.Shopify.surface : Theme.settingsCardFill)
                .shadow(color: Theme.panelElevatedShadow, radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: isShopify ? 8 : 6, style: isShopify ? .circular : .continuous)
                .strokeBorder(isShopify ? Theme.Shopify.border : Theme.borderColor, lineWidth: 1)
        }
    }
}

// MARK: - Host (root overlay)

/// Renders the active tooltip above all panel/settings content and clamps it on-screen.
struct HoverTooltipHost: View {
    @Bindable var controller: HoverTooltipController
    @Environment(AppState.self) private var appState
    @State private var bubbleSize: CGSize = .zero

    private var isShopify: Bool {
        appState.settings.widgetThemePreference.isShopify
    }

    var body: some View {
        GeometryReader { container in
            if let presentation = controller.presentation {
                let origin = HoverTooltipController.clampedOrigin(
                    anchor: presentation.anchor,
                    tooltipSize: bubbleSize,
                    container: container.size,
                    gap: presentation.gap,
                    verticalAnchor: presentation.verticalAnchor,
                    verticalBand: presentation.verticalBand
                )
                HoverTooltipBubble(
                    text: presentation.text,
                    shortcut: presentation.shortcut,
                    isShopify: isShopify
                )
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { bubbleSize = geo.size }
                            .onChange(of: geo.size) { _, size in
                                bubbleSize = size
                            }
                    }
                }
                // Stable identity across adjacent swaps so the bubble doesn’t remount.
                .opacity(bubbleSize.width > 0 && bubbleSize.height > 0 ? 1 : 0)
                .position(
                    x: origin.x + max(bubbleSize.width, 1) / 2,
                    y: origin.y + max(bubbleSize.height, 1) / 2
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: controller.presentation == nil)
    }
}

// MARK: - Modifier

/// Arms a delayed present into `HoverTooltipController` using the shared coordinate space.
struct HoverTooltipModifier: ViewModifier {
    let text: String
    var shortcut: KeyCombo? = nil
    /// Delay before the tooltip appears. Default 1s — earlier than the system tooltip.
    var delay: Duration = .seconds(1)
    var gap: CGFloat = HoverTooltipController.anchorGap
    var verticalAnchor: HoverTooltipController.VerticalAnchor = .top
    var verticalBand: CGRect? = nil

    @Environment(\.hoverTooltipController) private var tooltips
    @State private var token = UUID()
    @State private var isHovering = false
    @State private var isPresented = false
    @State private var anchor: CGRect = .zero
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    let frame = geo.frame(in: .named(HoverTooltipController.coordinateSpaceName))
                    Color.clear
                        .onAppear { anchor = frame }
                        .onChange(of: frame) { _, newFrame in
                            anchor = newFrame
                            if isPresented {
                                tooltips?.updateAnchor(
                                    token: token,
                                    anchor: newFrame,
                                    verticalBand: verticalBand
                                )
                            }
                        }
                }
            }
            .onChange(of: verticalBand) { _, band in
                if isPresented {
                    tooltips?.updateAnchor(token: token, anchor: anchor, verticalBand: band)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                showTask?.cancel()
                showTask = nil
                if hovering {
                    // Neighbor already showing the bubble — claim it immediately.
                    if tooltips?.isShowing == true {
                        presentNow(animated: false)
                        return
                    }
                    showTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: delay)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled, isHovering else { return }
                        presentNow(animated: true)
                    }
                } else {
                    scheduleDismissIfNeeded()
                }
            }
            .onDisappear {
                showTask?.cancel()
                scheduleDismissIfNeeded()
            }
    }

    private func presentNow(animated: Bool) {
        guard let tooltips else { return }
        let apply = {
            tooltips.present(
                token: token,
                text: text,
                shortcut: shortcut,
                anchor: anchor,
                gap: gap,
                verticalAnchor: verticalAnchor,
                verticalBand: verticalBand
            )
            isPresented = true
        }
        if animated {
            withAnimation(.easeOut(duration: 0.15), apply)
        } else {
            apply()
        }
    }

    private func scheduleDismissIfNeeded() {
        guard isPresented, let tooltips else {
            isPresented = false
            return
        }
        isPresented = false
        tooltips.scheduleDismiss(token: token)
    }
}

extension View {
    /// Hover tooltip hosted at the nearest `HoverTooltipHost`, with optional shortcut chrome.
    func hoverTooltip(
        _ text: String,
        shortcut: KeyCombo? = nil,
        delay: Duration = .seconds(1),
        gap: CGFloat = HoverTooltipController.anchorGap,
        verticalAnchor: HoverTooltipController.VerticalAnchor = .top,
        verticalBand: CGRect? = nil
    ) -> some View {
        modifier(
            HoverTooltipModifier(
                text: text,
                shortcut: shortcut,
                delay: delay,
                gap: gap,
                verticalAnchor: verticalAnchor,
                verticalBand: verticalBand
            )
        )
    }

    /// Coordinate space + root overlay required by `hoverTooltip`.
    func hoverTooltipContainer(controller: HoverTooltipController) -> some View {
        self
            .coordinateSpace(name: HoverTooltipController.coordinateSpaceName)
            .environment(\.hoverTooltipController, controller)
            .overlay {
                HoverTooltipHost(controller: controller)
            }
    }
}
