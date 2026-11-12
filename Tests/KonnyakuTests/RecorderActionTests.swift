import Carbon.HIToolbox
import XCTest
@testable import Konnyaku

final class RecorderActionTests: XCTestCase {
    private let escape = UInt16(kVK_Escape)
    private let tab = UInt16(kVK_Tab)
    private let space = UInt16(kVK_Space)
    private let returnKey = UInt16(kVK_Return)
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
        XCTAssertEqual(action(tab, shiftKey | cmdKey), .record)
    }

    func testRepeatsAreIgnored() {
        XCTAssertEqual(action(space, isRepeat: true), .ignore)
        XCTAssertEqual(action(returnKey, isRepeat: true), .ignore)
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
    }

    func testPlainSpaceAndReturnStartRecording() {
        let noModifiers = UInt32(0)
        XCTAssertTrue(RecorderView.startsRecording(keyCode: space, modifiers: noModifiers))
        XCTAssertTrue(RecorderView.startsRecording(keyCode: returnKey, modifiers: noModifiers))
    }

    func testOtherKeysDoNotStartRecording() {
        let noModifiers = UInt32(0)
        XCTAssertFalse(RecorderView.startsRecording(keyCode: tab, modifiers: noModifiers))
        XCTAssertFalse(RecorderView.startsRecording(keyCode: escape, modifiers: noModifiers))
        XCTAssertFalse(RecorderView.startsRecording(keyCode: letterT, modifiers: noModifiers))
        // ⇧Space and ⌥Return are someone else's.
        XCTAssertFalse(RecorderView.startsRecording(keyCode: space, modifiers: UInt32(shiftKey)))
        XCTAssertFalse(RecorderView.startsRecording(keyCode: returnKey, modifiers: UInt32(optionKey)))
    }
}
