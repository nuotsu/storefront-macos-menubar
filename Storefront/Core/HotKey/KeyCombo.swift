import Carbon.HIToolbox
import Foundation
import AppKit
import SwiftUI

/// A keyboard shortcut, stored in Carbon's key-code + modifier-mask shape since that's
/// what `RegisterEventHotKey` needs directly (see `GlobalHotKeyManager`).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt32

    static let `default` = KeyCombo(
        keyCode: UInt32(kVK_ANSI_S),
        modifierFlags: UInt32(cmdKey | optionKey | controlKey)
    )

    static let openAdminDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_A),
        modifierFlags: 0
    )

    static let openOnlineStoreDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_O),
        modifierFlags: 0
    )

    static let openSupportDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_H),
        modifierFlags: 0
    )

    static let focusSearchDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_Slash),
        modifierFlags: 0
    )

    static let toggleLinkSearchDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_S),
        modifierFlags: UInt32(controlKey)
    )

    static let openCreateLinkDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_A),
        modifierFlags: UInt32(controlKey)
    )

    var displayString: String {
        var result = ""
        if modifierFlags & UInt32(controlKey) != 0 { result += "⌃" }
        if modifierFlags & UInt32(optionKey) != 0 { result += "⌥" }
        if modifierFlags & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifierFlags & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyCodeToDisplayString(keyCode)
        return result
    }

    /// Canonical lowercase-letter/digit → key-code table — the single source of truth
    /// shared with `HotKeyRecorderView`'s key capture, so the two can't drift out of sync.
    static let alphanumericKeyCodes: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    /// Reverse of `alphanumericKeyCodes`, derived once so key-code → character lookups
    /// (display glyphs, mnemonics, menu equivalents) don't each scan the table.
    private static let alphanumericCharacters: [Int: Character] = Dictionary(
        uniqueKeysWithValues: alphanumericKeyCodes.map { ($0.value, $0.key) }
    )

    private static let alphanumericDisplayStrings: [Int: String] = alphanumericCharacters.mapValues {
        String($0).uppercased()
    }

    private static let namedKeyDisplayStrings: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_Slash: "/",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Covers the common ANSI/QWERTY keys used for hotkeys. Non-QWERTY layouts may show
    /// the wrong glyph for punctuation keys — a documented, common simplification (full
    /// layout-aware translation needs `UCKeyTranslate`, overkill for this use case).
    private static func keyCodeToDisplayString(_ keyCode: UInt32) -> String {
        alphanumericDisplayStrings[Int(keyCode)] ?? namedKeyDisplayStrings[Int(keyCode)] ?? "Key\(keyCode)"
    }

    /// Letter to hint in a label when this combo is a bare letter key; `nil` when the
    /// combo has modifiers or isn't a letter (digits, Escape, arrows, etc.).
    var mnemonicLetter: Character? {
        guard modifierFlags == 0,
              let letter = Self.alphanumericCharacters[Int(keyCode)],
              letter.isLetter
        else { return nil }
        return letter
    }

    /// This combo's active modifiers as SF Symbol names, in the conventional Mac ordering
    /// (⌃⌥⇧⌘) — used by `KeyComboView` instead of the Unicode modifier characters.
    var modifierSymbolNames: [String] {
        var names: [String] = []
        if modifierFlags & UInt32(controlKey) != 0 { names.append("control") }
        if modifierFlags & UInt32(optionKey) != 0 { names.append("option") }
        if modifierFlags & UInt32(shiftKey) != 0 { names.append("shift") }
        if modifierFlags & UInt32(cmdKey) != 0 { names.append("command") }
        return names
    }

    /// This combo's main key, for `KeyComboView` — an SF Symbol where a good match
    /// exists (Return, Escape, Delete, arrows), otherwise the same plain text
    /// `displayString` already uses (letters, digits, Tab, Space, function keys).
    enum KeyGlyph {
        case symbol(String)
        case text(String)
    }

    var keyGlyph: KeyGlyph {
        switch Int(keyCode) {
        case kVK_Return: return .symbol("return")
        case kVK_Escape: return .symbol("escape")
        case kVK_Delete: return .symbol("delete.left")
        case kVK_LeftArrow: return .symbol("arrow.left")
        case kVK_RightArrow: return .symbol("arrow.right")
        case kVK_UpArrow: return .symbol("arrow.up")
        case kVK_DownArrow: return .symbol("arrow.down")
        default: return .text(Self.keyCodeToDisplayString(keyCode))
        }
    }

    /// This combo as an `NSMenuItem.keyEquivalent`/`keyEquivalentModifierMask` pair, for
    /// showing the real configured shortcut natively in the status-item menu. Empty
    /// string if the key isn't a plain letter/digit (arrows, function keys, etc. have no
    /// direct `NSMenuItem` representation worth attempting) — the item just shows no glyph.
    var nsMenuKeyEquivalent: (key: String, mask: NSEvent.ModifierFlags) {
        var mask: NSEvent.ModifierFlags = []
        if modifierFlags & UInt32(controlKey) != 0 { mask.insert(.control) }
        if modifierFlags & UInt32(optionKey) != 0 { mask.insert(.option) }
        if modifierFlags & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if modifierFlags & UInt32(cmdKey) != 0 { mask.insert(.command) }
        guard let letter = Self.alphanumericCharacters[Int(keyCode)] else {
            return ("", mask)
        }
        return (String(letter), mask)
    }

    /// Builds a combo from a SwiftUI `KeyPress` (used by the Settings recorder).
    static func from(keyCode: UInt32, commandDown: Bool, optionDown: Bool, controlDown: Bool, shiftDown: Bool) -> KeyCombo {
        var mods: UInt32 = 0
        if commandDown { mods |= UInt32(cmdKey) }
        if optionDown { mods |= UInt32(optionKey) }
        if controlDown { mods |= UInt32(controlKey) }
        if shiftDown { mods |= UInt32(shiftKey) }
        return KeyCombo(keyCode: keyCode, modifierFlags: mods)
    }

    /// Whether a SwiftUI key press matches this combo (panel-local shortcut handling).
    func matches(_ keyPress: KeyPress) -> Bool {
        guard let code = Self.keyCode(for: keyPress.key), UInt32(code) == keyCode else { return false }
        let press: UInt32 = {
            var mods: UInt32 = 0
            if keyPress.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
            if keyPress.modifiers.contains(.option) { mods |= UInt32(optionKey) }
            if keyPress.modifiers.contains(.control) { mods |= UInt32(controlKey) }
            if keyPress.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
            return mods
        }()
        return press == modifierFlags
    }

    /// Carbon key code for a SwiftUI `KeyEquivalent` — shared by the recorder and `matches(_:)`.
    static func keyCode(for key: KeyEquivalent) -> Int? {
        switch key {
        case .space: return kVK_Space
        case .return: return kVK_Return
        case .tab: return kVK_Tab
        case .delete: return kVK_Delete
        case .escape: return kVK_Escape
        case .upArrow: return kVK_UpArrow
        case .downArrow: return kVK_DownArrow
        case .leftArrow: return kVK_LeftArrow
        case .rightArrow: return kVK_RightArrow
        default:
            let character = key.character
            if character == "/" { return kVK_ANSI_Slash }
            guard let lowerChar = String(character).lowercased().first else { return nil }
            return alphanumericKeyCodes[lowerChar]
        }
    }
}

/// Renders a `KeyCombo` as SF Symbol modifier glyphs (matching how macOS itself draws
/// keyboard shortcuts) instead of the Unicode modifier characters — with a plain-text
/// fallback for the main key when no reasonable symbol exists (letters, digits, etc.).
struct KeyComboView: View {
    let combo: KeyCombo
    var font: Font = .system(size: 11, weight: .medium)
    /// Shared glyph box so SF Symbols and text keys share one height (no keycap jump).
    var glyphHeight: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(combo.modifierSymbolNames, id: \.self) { name in
                Image(systemName: name)
                    .frame(height: glyphHeight)
            }
            switch combo.keyGlyph {
            case .symbol(let name):
                Image(systemName: name)
                    .frame(height: glyphHeight)
            case .text(let text):
                Text(text)
                    .frame(height: glyphHeight)
            }
        }
        .font(font)
        .lineLimit(1)
        .frame(height: glyphHeight)
    }
}
