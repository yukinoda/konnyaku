import Carbon.HIToolbox
import XCTest
@testable import Konnyaku

final class RecorderActionTests: XCTestCase {
    private let escape = UInt16(kVK_Escape)
    private let tab = UInt16(kVK_Tab)
    private let space = UInt16(kVK_Space)
    private let returnKey = UInt16(kVK_Return)
    private let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    private let letterT = UInt16(kVK_ANSI_T)

    private func action(
        _ keyCode: UInt16,
        _ modifiers: Int = 0,
        isRepeat: Bool = false
    ) -> RecorderView.RecordingAction {
        RecorderView.recordingAction(
            keyCode: keyCode,
            modifiers: UInt32(modifiers),
            isRepeat: isRepeat
        )
    }

    private func startsRecording(_ keyCode: UInt16, _ modifiers: Int = 0) -> Bool {
        RecorderView.startsRecording(keyCode: keyCode, modifiers: UInt32(modifiers))
    }

    func testPlainEscCancels() {
        XCTAssertEqual(action(escape), .cancel)
    }

    func testEscWithModifiersIsRecorded() {
        XCTAssertEqual(action(escape, optionKey), .record)
        XCTAssertEqual(action(escape, shiftKey), .record)
        XCTAssertEqual(action(escape, cmdKey), .record)
    }

    func testTabAndShiftTabMoveFocus() {
        XCTAssertEqual(action(tab), .cancelAndMoveFocus)
        XCTAssertEqual(action(tab, shiftKey), .cancelAndMoveFocus)
    }

    func testTabWithOtherModifiersIsRecorded() {
        XCTAssertEqual(action(tab, controlKey), .record)
        XCTAssertEqual(action(tab, optionKey), .record)
        XCTAssertEqual(action(tab, cmdKey), .record)
        XCTAssertEqual(action(tab, shiftKey | cmdKey), .record)
    }

    func testRepeatsAreIgnored() {
        XCTAssertEqual(action(space, isRepeat: true), .ignore)
        XCTAssertEqual(action(returnKey, isRepeat: true), .ignore)
        XCTAssertEqual(action(keypadEnter, isRepeat: true), .ignore)
        XCTAssertEqual(action(escape, isRepeat: true), .ignore)
        XCTAssertEqual(action(tab, isRepeat: true), .ignore)
        XCTAssertEqual(action(letterT, controlKey | optionKey, isRepeat: true), .ignore)
    }

    func testOtherKeysAreRecorded() {
        XCTAssertEqual(action(letterT, controlKey | optionKey), .record)
        XCTAssertEqual(action(letterT), .record)
        // Space and Return don't start anything once recording.
        XCTAssertEqual(action(space), .record)
        XCTAssertEqual(action(returnKey), .record)
        XCTAssertEqual(action(keypadEnter), .record)
    }

    func testPlainSpaceAndReturnStartRecording() {
        XCTAssertTrue(startsRecording(space))
        XCTAssertTrue(startsRecording(returnKey))
    }

    func testPlainKeypadEnterStartsRecording() {
        XCTAssertTrue(startsRecording(keypadEnter))
    }

    func testOtherKeysDoNotStartRecording() {
        XCTAssertFalse(startsRecording(tab))
        XCTAssertFalse(startsRecording(escape))
        XCTAssertFalse(startsRecording(letterT))
        // ⇧Space and ⌥Return are someone else's.
        XCTAssertFalse(startsRecording(space, shiftKey))
        XCTAssertFalse(startsRecording(returnKey, optionKey))
        XCTAssertFalse(startsRecording(keypadEnter, optionKey))
    }
}
