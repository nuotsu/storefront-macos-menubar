import SwiftUI
import AppKit

/// Walks to the nearby `NSTextField` under a SwiftUI `TextField` and applies AppKit
/// tuning that SwiftUI does not expose: no focus ring (avoids focus layout shift).
/// Caret color is deliberately not handled here — use `CaretTintedTextField` when the
/// caret must match a custom accent.
struct TextFieldAppKitTuning: NSViewRepresentable {
    func makeNSView(context: Context) -> TunerView {
        let view = TunerView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: TunerView, context: Context) {
        nsView.applyTuning()
    }

    final class TunerView: NSView {
        /// `updateNSView` fires on every panel re-render, and resolving the field means
        /// walking up the superview chain and recursing through sibling subtrees. Hold
        /// on to the field we found instead of re-walking for it each time.
        private weak var tunedField: NSTextField?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tunedField = nil
            applyTuning()
        }

        func applyTuning() {
            guard let field = resolvedField() else { return }
            field.focusRingType = .none
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            if let editor = field.currentEditor() as? NSTextView {
                editor.textContainerInset = .zero
                editor.textContainer?.lineFragmentPadding = 0
            }
        }

        private func resolvedField() -> NSTextField? {
            if let tunedField, let window, tunedField.window === window {
                return tunedField
            }
            let field = Self.nearestTextField(from: self)
            tunedField = field
            return field
        }

        private static func nearestTextField(from view: NSView) -> NSTextField? {
            var node: NSView? = view.superview
            while let current = node {
                if let field = current as? NSTextField {
                    return field
                }
                if let field = current.subviews.compactMap({ $0 as? NSTextField }).first {
                    return field
                }
                for sibling in current.subviews where sibling !== view {
                    if let field = findTextField(in: sibling) {
                        return field
                    }
                }
                node = current.superview
            }
            return nil
        }

        private static func findTextField(in root: NSView) -> NSTextField? {
            if let field = root as? NSTextField { return field }
            for child in root.subviews {
                if let field = findTextField(in: child) { return field }
            }
            return nil
        }
    }
}

// MARK: - Owned AppKit text view (stable layout + caret tint)

/// Single-line plain field that owns its caret color and drawing path. Prefer this over
/// SwiftUI `TextField` / `NSTextField` for card-row search: the window’s shared field
/// editor both resets `insertionPointColor` and lays out text with different insets than
/// the idle cell, which caused accent-caret loss and focus layout shift.
struct CaretTintedTextField: NSViewRepresentable {
    @Binding var text: String
    var caretColor: NSColor
    var fontSize: CGFloat = 11.5
    var onSubmit: () -> Void = {}
    /// Bumped (non-zero) to select the entire contents once the field can take focus —
    /// used after ⌃S so leftover query text is replace-ready.
    var selectAllGeneration: UInt = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CaretTintedNSTextView {
        let view = CaretTintedNSTextView(fontSize: fontSize)
        view.delegate = context.coordinator
        view.caretColor = caretColor
        view.string = text
        return view
    }

    func updateNSView(_ nsView: CaretTintedNSTextView, context: Context) {
        context.coordinator.parent = self
        nsView.caretColor = caretColor
        if nsView.string != text {
            nsView.string = text
        }
        if selectAllGeneration != 0,
           selectAllGeneration != context.coordinator.lastSelectAllGeneration
        {
            context.coordinator.lastSelectAllGeneration = selectAllGeneration
            // Don't call makeFirstResponder here — that bypasses SwiftUI `@FocusState` and
            // leaves AppKit focus stranded after the field is torn down (⌃S collapse),
            // which silently kills panel `.onKeyPress` (arrows included). Selection is
            // applied after FocusState has already focused this view.
            DispatchQueue.main.async {
                guard !nsView.string.isEmpty else { return }
                nsView.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaretTintedTextField
        var lastSelectAllGeneration: UInt = 0

        init(_ parent: CaretTintedTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// Single-line `NSTextView` that keeps the same layout metrics focused and blurred, and
/// owns `insertionPointColor` (unlike `NSTextField`’s shared field editor).
final class CaretTintedNSTextView: NSTextView {
    private let fontSize: CGFloat

    var caretColor: NSColor {
        get { insertionPointColor }
        set { insertionPointColor = newValue }
    }

    init(fontSize: CGFloat) {
        self.fontSize = fontSize
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        font = .systemFont(ofSize: fontSize)
        textColor = .labelColor
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width, .height]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        focusRingType = .none
        textContainerInset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncLayoutMetrics()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncLayoutMetrics()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Leaving the hierarchy while first responder leaves AppKit with nil focus;
        // resign explicitly so the panel can reclaim `.onKeyPress`.
        if newWindow == nil, let window, window.firstResponder === self {
            window.makeFirstResponder(window.contentView)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Vertical centering via equal top/bottom container inset; horizontal flush. Same
    /// path while focused and blurred, so the caret cannot nudge text.
    private func syncLayoutMetrics() {
        textContainer?.lineFragmentPadding = 0
        let font = self.font ?? .systemFont(ofSize: fontSize)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let verticalInset = max(0, floor((bounds.height - lineHeight) / 2))
        let inset = NSSize(width: 0, height: verticalInset)
        if textContainerInset != inset {
            textContainerInset = inset
        }
        if let textContainer {
            textContainer.size = NSSize(
                width: max(0, bounds.width - inset.width * 2),
                height: max(0, bounds.height - inset.height * 2)
            )
        }
    }
}

extension NSColor {
    /// Opaque sRGB color from a `"rrggbb"` / `"#rrggbb"` hex string.
    convenience init(hex: String) {
        let (r, g, b) = HexColor.components(hex)
        self.init(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}
