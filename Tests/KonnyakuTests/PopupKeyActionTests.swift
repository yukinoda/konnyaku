import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Konnyaku

final class PopupKeyActionTests: XCTestCase {
    private let escape = UInt16(kVK_Escape)
    private let returnKey = UInt16(kVK_Return)
    private let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    private let keyE = UInt16(kVK_ANSI_E)

    private func action(
        _ keyCode: UInt16,
        _ modifierFlags: NSEvent.ModifierFlags = [],
        character: String? = nil,
        isComposing: Bool = false,
        isExpanded: Bool = false
    ) -> TranslatePanelController.KeyAction? {
        TranslatePanelController.keyAction(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            charactersIgnoringModifiers: character,
            isComposing: isComposing,
            isExpanded: isExpanded
        )
    }

    func testEscapeClosesInBothModes() {
        XCTAssertEqual(action(escape, character: "\u{1B}"), .close)
        XCTAssertEqual(action(escape, character: "\u{1B}", isExpanded: true), .close)
    }

    func testEscapeClosesWhateverTheModifiers() {
        XCTAssertEqual(action(escape, .shift, character: "\u{1B}"), .close)
        XCTAssertEqual(action(escape, .command, character: "\u{1B}", isExpanded: true), .close)
    }

    func testReturnCopiesInTheCompactPopup() {
        XCTAssertEqual(action(returnKey, character: "\r"), .copyAndClose)
    }

    func testKeypadEnterCopiesInTheCompactPopup() {
        XCTAssertEqual(action(keypadEnter, character: "\r"), .copyAndClose)
    }

    /// Real keypad events carry the numeric-pad flag, which isn't a modifier.
    func testKeypadEnterWithTheNumericPadFlagStillCopies() {
        let action = action(keypadEnter, .numericPad, character: "\r")
        XCTAssertEqual(action, .copyAndClose)
    }

    func testKeypadEnterBelongsToTheEditorWhenExpanded() {
        XCTAssertNil(action(keypadEnter, character: "\r", isExpanded: true))
    }

    func testKeypadEnterWithAShortcutModifierIsNotCopy() {
        let modifiers: [NSEvent.ModifierFlags] = [.shift, .command, .option, .control]
        for modifier in modifiers {
            XCTAssertNil(action(keypadEnter, modifier, character: "\r"), "\(modifier)")
        }
    }

    func testReturnBelongsToTheEditorWhenExpanded() {
        XCTAssertNil(action(returnKey, character: "\r", isExpanded: true))
    }

    func testReturnWithAShortcutModifierIsNotCopy() {
        let modifiers: [NSEvent.ModifierFlags] = [.shift, .command, .option, .control]
        for modifier in modifiers {
            XCTAssertNil(action(returnKey, modifier, character: "\r"), "\(modifier)")
        }
    }

    func testCapsLockAndFnDoNotChangeAShortcut() {
        let ignored: NSEvent.ModifierFlags = [.capsLock, .function]
        XCTAssertEqual(action(returnKey, ignored, character: "\r"), .copyAndClose)
        let commandWithIgnored = ignored.union(.command)
        XCTAssertEqual(action(keyE, commandWithIgnored, character: "e"), .expand)
    }

    func testCommandEExpandsTheCompactPopup() {
        XCTAssertEqual(action(keyE, .command, character: "e"), .expand)
    }

    func testCommandEMatchesUppercase() {
        XCTAssertEqual(action(keyE, .command, character: "E"), .expand)
    }

    /// On Dvorak the key that types "e" is at QWERTY's D.
    func testCommandEMatchesByCharacterNotKeyCode() {
        let dvorakE = UInt16(kVK_ANSI_D)
        XCTAssertEqual(action(dvorakE, .command, character: "e"), .expand)
        XCTAssertNil(action(keyE, .command, character: "."))
    }

    func testCommandEDoesNothingWhenExpanded() {
        XCTAssertNil(action(keyE, .command, character: "e", isExpanded: true))
    }

    func testEWithoutExactlyCommandIsNotExpand() {
        XCTAssertNil(action(keyE, character: "e"))
        XCTAssertNil(action(keyE, [.shift, .command], character: "e"))
        XCTAssertNil(action(keyE, [.option, .command], character: "e"))
        XCTAssertNil(action(keyE, .control, character: "e"))
    }

    func testOtherKeysPassThrough() {
        XCTAssertNil(action(UInt16(kVK_ANSI_C), .command, character: "c"))
        XCTAssertNil(action(UInt16(kVK_ANSI_A), character: "a"))
        XCTAssertNil(action(keyE, .command, character: nil))
    }

    /// Return confirms a candidate and Esc cancels one; neither may copy or
    /// close while the IME is composing.
    func testComposingPassesEveryKeyThrough() {
        for isExpanded in [false, true] {
            let escapeAction = action(
                escape,
                character: "\u{1B}",
                isComposing: true,
                isExpanded: isExpanded
            )
            let returnAction = action(
                returnKey,
                character: "\r",
                isComposing: true,
                isExpanded: isExpanded
            )
            let keypadEnterAction = action(
                keypadEnter,
                character: "\r",
                isComposing: true,
                isExpanded: isExpanded
            )
            let commandEAction = action(
                keyE,
                .command,
                character: "e",
                isComposing: true,
                isExpanded: isExpanded
            )
            let mode = isExpanded ? "expanded" : "compact"
            XCTAssertNil(escapeAction, mode)
            XCTAssertNil(returnAction, mode)
            XCTAssertNil(keypadEnterAction, mode)
            XCTAssertNil(commandEAction, mode)
        }
    }

    /// A ⌘ shortcut the popup matches by character must be one HotKey
    /// refuses as the global hotkey, or the hotkey would swallow it. Esc is
    /// matched by key code and closes whatever the modifiers, so it isn't a
    /// ⌘ shortcut in this sense.
    func testEveryCommandShortcutIsReservedByHotKey() {
        // ⌘ with every combination of ⇧, ⌥ and ⌃.
        let modifierCombinations: [NSEvent.ModifierFlags] = [
            [.command],
            [.command, .shift],
            [.command, .option],
            [.command, .control],
            [.command, .shift, .option],
            [.command, .shift, .control],
            [.command, .option, .control],
            [.command, .shift, .option, .control],
        ]
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789,./;'[]-=`".map(String.init)
        // The popup matches ⌘ shortcuts by character, so any key will do.
        let anyKeyCode = UInt16(kVK_ANSI_A)
        var handledCount = 0
        for isExpanded in [false, true] {
            for modifiers in modifierCombinations {
                for character in characters {
                    let keyAction = action(
                        anyKeyCode,
                        modifiers,
                        character: character,
                        isExpanded: isExpanded
                    )
                    if keyAction == nil {
                        continue
                    }
                    handledCount += 1
                    let carbonModifiers = HotKey.carbonModifiers(from: modifiers)
                    let hotKey = HotKey(keyCode: UInt32(anyKeyCode), carbonModifiers: carbonModifiers)
                    let block = hotKey.block(commandCharacters: [character])
                    XCTAssertEqual(block, .konnyakuShortcut, "\(modifiers) \(character)")
                }
            }
        }
        // Guards against the loop above silently checking nothing.
        XCTAssertGreaterThan(handledCount, 0)
    }
}
