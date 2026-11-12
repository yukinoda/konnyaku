import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Konnyaku

@MainActor
final class PopupKeyActionTests: XCTestCase {
    private let escape = UInt16(kVK_Escape)
    private let returnKey = UInt16(kVK_Return)
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
            XCTAssertNil(action(escape, character: "\u{1B}", isComposing: true, isExpanded: isExpanded))
            XCTAssertNil(action(returnKey, character: "\r", isComposing: true, isExpanded: isExpanded))
            XCTAssertNil(action(keyE, .command, character: "e", isComposing: true, isExpanded: isExpanded))
        }
    }

    /// A ⌘ shortcut the popup handles must be one HotKey refuses as the
    /// global hotkey, or the hotkey would swallow it.
    func testEveryCommandShortcutIsReservedByHotKey() {
        let modifierCombinations: [NSEvent.ModifierFlags] = [
            .command,
            [.shift, .command],
            [.option, .command],
            [.control, .command],
        ]
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789,./;'[]-=`".map(String.init)
        var handledCount = 0
        for modifiers in modifierCombinations {
            for character in characters {
                let handled = action(keyE, modifiers, character: character)
                if handled == nil {
                    continue
                }
                handledCount += 1
                let carbonModifiers = HotKey.carbonModifiers(from: modifiers)
                let hotKey = HotKey(keyCode: UInt32(keyE), carbonModifiers: carbonModifiers)
                let block = hotKey.block(commandCharacters: [character])
                XCTAssertEqual(block, .konnyakuShortcut, "\(modifiers) \(character)")
            }
        }
        // Guards against the loop above silently checking nothing.
        XCTAssertGreaterThan(handledCount, 0)
    }
}
