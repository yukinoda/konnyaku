import Foundation

struct GlossaryEntry {
    let source: String
    let target: String
}

enum Form: String {
    case plain
    case polite
}

/// One piece of a prompt. Template pieces may contain special tokens such
/// as `<|plamo:tag|>`; user pieces are always tokenized as plain text.
struct PromptSegment: Equatable {
    let text: String
    let isTemplate: Bool
}

/// Builds a PFML3 translation prompt. The BOS token is not included;
/// the tokenizer adds it.
struct PFML3Prompt {
    let text: String
    let target: String
    var context: String?
    var glossary: [GlossaryEntry] = []
    var form: Form?

    func build() -> String {
        segments().map { $0.text }.joined()
    }

    func segments() -> [PromptSegment] {
        var result: [PromptSegment] = []
        func template(_ text: String) {
            result.append(PromptSegment(text: text, isTemplate: true))
        }
        func user(_ text: String) {
            let safeText = Self.neutralizingSpecialTokens(in: text)
            result.append(PromptSegment(text: safeText, isTemplate: false))
        }

        template("<|plamo:tag|>dataset<|plamo:msg|>translation")

        if let context, !context.isEmpty {
            template("<|plamo:tag|>context<|plamo:msg|>")
            user(context)
        }

        if !glossary.isEmpty {
            template("<|plamo:tag|>glossary")
            for entry in glossary {
                template("<|plamo:index|>")
                user(entry.source)
                template("<|plamo:item|>")
                user(entry.target)
            }
        }

        template("<|plamo:tag|>input<|plamo:msg|>")
        user(text)

        var tail = "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>\(target)"
        if let form {
            tail += "<|plamo:key|>form<|plamo:val|>\(form.rawValue)"
        }
        tail += "<|plamo:msg|>"
        template(tail)
        return result
    }

    /// The PLaMo vocabulary matches its special tokens even when the
    /// tokenizer is told not to parse them, so user text must never contain
    /// the `<|plamo:` marker that every special token starts with.
    static func neutralizingSpecialTokens(in text: String) -> String {
        text.replacingOccurrences(of: "<|plamo:", with: "< |plamo:")
    }
}

enum TargetLanguage {
    static let choices: [(code: String, name: String)] = [
        ("en", "English"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
    ]

    /// Kana, kanji and the marks written only in Japanese count. Kanji count
    /// even though Chinese shares them, because the users are Japanese.
    /// Marks that also turn up in non-Japanese text (・ ゠ ゛ ゜ ー and their
    /// half-width forms) are left out, so "USB・HDMI" stays English.
    /// konnyaku.py's JAPANESE_RANGES must match this table; check-cli.py
    /// compares the two, and Tests/auto-target-cases.json tests both.
    private static let japaneseRanges: [ClosedRange<UInt32>] = [
        0x3005...0x3007,  // 々 〆 and 〇
        0x3031...0x3035,  // Vertical kana iteration marks 〱 to 〵
        0x303B...0x303C,  // Vertical kanji iteration mark 〻 and masu mark 〼
        0x3041...0x3096,  // Hiragana letters
        0x309D...0x309F,  // Hiragana iteration marks ゝ ゞ and digraph ゟ
        0x30A1...0x30FA,  // Katakana letters
        0x30FD...0x30FF,  // Katakana iteration marks ヽ ヾ and digraph ヿ
        0x31F0...0x31FF,  // Katakana Phonetic Extensions (ㇰ)
        0x3400...0x4DBF,  // CJK Extension A
        0x4E00...0x9FFF,  // CJK Unified Ideographs
        0xF900...0xFAFF,  // CJK Compatibility Ideographs (﨑)
        0xFF66...0xFF6F,  // Half-width katakana ｦ to ｯ
        0xFF71...0xFF9D,  // Half-width katakana ｱ to ﾝ
        0x1B000...0x1B16F,  // Kana Supplement to Small Kana Extension (hentaigana)
        0x20000...0x3FFFF,  // Ideographic planes: Extension B and later (𠮷)
    ]

    /// Text containing any character in `japaneseRanges` goes to English,
    /// anything else goes to Japanese. Kanji-only input counts as Japanese on
    /// purpose: the target users are Japanese.
    static func auto(for text: String) -> String {
        let isJapanese = text.unicodeScalars.contains { scalar in
            japaneseRanges.contains { $0.contains(scalar.value) }
        }
        return isJapanese ? "en" : "ja"
    }
}
