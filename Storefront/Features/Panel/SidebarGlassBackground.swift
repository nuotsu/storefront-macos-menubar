import AppKit
import SwiftUI

/// Sidebar / card / header chrome — prefers macOS 26 `NSGlassEffectView`, falls back to
/// `NSVisualEffectView` (cmux `SidebarVisualEffectBackground` recipe).
///
/// Always installed as a **background**: the representable’s root view returns `nil`
/// from `hitTest` so AppKit cannot steal clicks from SwiftUI controls on top
/// (same failure mode as `MouseTrackingOverlay` without a passthrough `hitTest`).
struct SidebarGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> PassthroughContainerView {
        let container = PassthroughContainerView()
        container.autoresizingMask = [.width, .height]

        let chrome: NSView
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: .zero)
            glass.autoresizingMask = [.width, .height]
            glass.wantsLayer = true
            applyCornerRadius(to: glass)
            applyDefaultGlassStyle(to: glass)
            chrome = glass
        } else {
            let view = NSVisualEffectView()
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layerContentsRedrawPolicy = .onSetNeedsDisplay
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            applyCornerRadius(to: view)
            chrome = view
        }

        chrome.frame = container.bounds
        container.addSubview(chrome)
        container.chromeView = chrome
        container.appliedCornerRadius = cornerRadius
        container.appliedMaterial = material
        container.appliedBlendingMode = blendingMode
        return container
    }

    /// SwiftUI calls this on every reconciliation pass, and there are ~12 of these live
    /// at once (the rail, every section card, the panel chrome). Re-applying blindly
    /// forced a vibrancy redraw — and, on the glass path, a selector lookup plus an
    /// `unsafeBitCast` trampoline — per view per render. Every value here is constant
    /// per call site, so after the first pass this is a no-op.
    func updateNSView(_ container: PassthroughContainerView, context: Context) {
        guard let chrome = container.chromeView else { return }
        // `container.layout()` already keeps the chrome's frame in sync.

        if container.appliedCornerRadius != cornerRadius {
            container.appliedCornerRadius = cornerRadius
            applyCornerRadius(to: chrome)
        }

        if chrome.className == "NSGlassEffectView" {
            // Style is fixed for every call site; applying once in `makeNSView` is enough.
            return
        }

        guard let visualEffect = chrome as? NSVisualEffectView else { return }
        guard container.appliedMaterial != material
            || container.appliedBlendingMode != blendingMode
            || visualEffect.state != .active
        else { return }

        container.appliedMaterial = material
        container.appliedBlendingMode = blendingMode
        visualEffect.material = material
        visualEffect.blendingMode = blendingMode
        visualEffect.state = .active
        visualEffect.needsDisplay = true
    }

    private func applyCornerRadius(to view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = cornerRadius > 0
        // `NSGlassEffectView` draws its own rounded shape; the layer radius alone
        // doesn't square it off.
        if view.className == "NSGlassEffectView",
           view.responds(to: NSSelectorFromString("setCornerRadius:"))
        {
            view.setValue(cornerRadius, forKey: "cornerRadius")
        }
    }

    /// Regular (frosted) liquid-glass style — the only style call sites use.
    private func applyDefaultGlassStyle(to glassView: NSView) {
        let styleSelector = NSSelectorFromString("setStyle:")
        if glassView.responds(to: styleSelector),
           let implementation = glassView.method(for: styleSelector)
        {
            typealias StyleSetter = @convention(c) (AnyObject, Selector, Int) -> Void
            let setter = unsafeBitCast(implementation, to: StyleSetter.self)
            setter(glassView, styleSelector, 0) // regular
        }
    }
}

/// Hosts glass / vibrancy chrome but never wins AppKit hit-testing.
final class PassthroughContainerView: NSView {
    var chromeView: NSView?
    /// Last values pushed onto `chromeView`, so `updateNSView` can skip re-applying
    /// (and re-rendering) an unchanged configuration.
    var appliedCornerRadius: CGFloat?
    var appliedMaterial: NSVisualEffectView.Material?
    var appliedBlendingMode: NSVisualEffectView.BlendingMode?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        chromeView?.frame = bounds
    }
}
