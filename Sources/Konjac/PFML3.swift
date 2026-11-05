import Foundation

struct GlossaryEntry {
    let source: String
    let target: String
}

enum Form: String {
    case plain
    case polite
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
        var prompt = "<|plamo:tag|>dataset<|plamo:msg|>translation"

        if let context, !context.isEmpty {
            prompt += "<|plamo:tag|>context<|plamo:msg|>\(context)"
        }

        if !glossary.isEmpty {
            prompt += "<|plamo:tag|>glossary"
            for entry in glossary {
                prompt += "<|plamo:index|>\(entry.source)<|plamo:item|>\(entry.target)"
            }
        }

        prompt += "<|plamo:tag|>input<|plamo:msg|>\(text)"
        prompt += "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>\(target)"

        if let form {
            prompt += "<|plamo:key|>form<|plamo:val|>\(form.rawValue)"
        }

        prompt += "<|plamo:msg|>"
        return prompt
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

    /// Japanese text (contains hiragana or katakana) goes to English,
    /// anything else goes to Japanese.
    static func auto(for text: String) -> String {
        let kanaRange: ClosedRange<UInt32> = 0x3040...0x30FF
        let hasKana = text.unicodeScalars.contains { kanaRange.contains($0.value) }
        return hasKana ? "en" : "ja"
    }
}
