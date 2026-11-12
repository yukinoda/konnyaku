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

    /// Text containing any character in `japaneseRanges` goes to English,
    /// anything else goes to Japanese. Kanji-only input counts as Japanese on
    /// purpose: the target users are Japanese.
    ///
    /// Only kana and kanji count. Marks also used outside Japanese text
    /// (・ ゠ ゛ ゜ ー and their half-width forms) are left out, so "USB・HDMI"
    /// stays English. konnyaku.py's JAPANESE_RANGES lists the same ranges,
    /// and Tests/auto-target-cases.json checks both.
    static func auto(for text: String) -> String {
        let japaneseRanges: [ClosedRange<UInt32>] = [
            0x3041...0x3096,  // Hiragana letters
            0x309D...0x309F,  // Hiragana iteration marks ゝ ゞ and ゟ
            0x30A1...0x30FA,  // Katakana letters
            0x30FD...0x30FF,  // Katakana iteration marks ヽ ヾ and ヿ
            0x31F0...0x31FF,  // Katakana Phonetic Extensions (ㇰ)
            0xFF66...0xFF6F,  // Half-width katakana ｦ to ｯ
            0xFF71...0xFF9D,  // Half-width katakana ｱ to ﾝ
            0x3005...0x3006,  // Kanji iteration mark 々 and 〆
            0x3400...0x4DBF,  // CJK Extension A
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xF900...0xFAFF,  // CJK Compatibility Ideographs (﨑)
            0x20000...0x3FFFF,  // Ideographic planes: Extension B and later (𠮷)
        ]
        let isJapanese = text.unicodeScalars.contains { scalar in
            japaneseRanges.contains { $0.contains(scalar.value) }
        }
        return isJapanese ? "en" : "ja"
    }
}
