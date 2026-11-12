import AppKit

/// Decides whether clipboard text is a new translation request. Pure: the
/// panel controller reads the clipboard and the model and passes the values
/// in, so these rules run without a pasteboard.
enum ClipboardRules {
    /// The text without surrounding whitespace, for comparing; nil if blank.
    static func trimmed(_ text: String?) -> String? {
        let result = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if result?.isEmpty == true {
            return nil
        }
        return result
    }

    /// Whether the user copied something since the panel was last shown,
    /// excluding Konnyaku's own copy and concealed data such as passwords
    /// from a password manager. Decided before the text is read. `types` is
    /// called only once both counts say the copy is new.
    static func isNewCopy(
        changeCount: Int,
        seenChangeCount: Int,
        ownCopyChangeCount: Int,
        types: () -> [NSPasteboard.PasteboardType]
    ) -> Bool {
        if changeCount == seenChangeCount {
            return false
        }
        if changeCount == ownCopyChangeCount {
            return false
        }
        if SelectionReader.isConcealed(types: types()) {
            return false
        }
        return true
    }

    /// Whether the text of a new copy is worth translating: not blank, and
    /// not Konnyaku's own text.
    static func isNewRequest(
        _ text: String?,
        sourceText: String,
        output: String,
        lastRunFailed: Bool
    ) -> Bool {
        if trimmed(text) == nil {
            return false
        }
        let isOwn = isOwnText(
            text,
            sourceText: sourceText,
            output: output,
            lastRunFailed: lastRunFailed
        )
        return !isOwn
    }

    /// Text the user copied out of Konnyaku itself (⌘C on the source or
    /// translation) is not a new request.
    private static func isOwnText(
        _ text: String?,
        sourceText: String,
        output: String,
        lastRunFailed: Bool
    ) -> Bool {
        let candidate = trimmed(text)
        // After a failed run, re-copying the source is a retry, not own text.
        let matchesSource = candidate == trimmed(sourceText)
        let isSource = matchesSource && !lastRunFailed
        let isOutput = candidate == trimmed(output)
        return isSource || isOutput
    }

    /// The seen change count after a selection read found nothing and the
    /// hotkey falls back to the clipboard. The restored clipboard is new only
    /// if it was new before the ⌘C.
    static func seenChangeCountAfterFallback(
        _ seen: Int,
        countBeforeCopy: Int?,
        restoredChangeCount: Int?
    ) -> Int {
        let wasSeen = countBeforeCopy == seen
        if wasSeen, let restoredCount = restoredChangeCount {
            return restoredCount
        }
        return seen
    }
}
