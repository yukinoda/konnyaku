#!/usr/bin/env -S uv run --locked --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "mlx-lm==0.32.2",
#     "mlx==0.32.4",
#     "transformers==5.22.2",
#     "numba==0.68.1",
# ]
# [tool.uv]
# exclude-newer = "2026-11-07T00:00:00Z"
# ///
"""konnyaku: local translation with PLaMo 3 Translate (MLX, Apple silicon).

  konnyaku "会議は来週の月曜日に変更されました。"     # ja -> en (auto)
  echo "This system is convenient." | konnyaku       # non-ja -> ja (auto)
  konnyaku -t fr "Hello" -g "Hello=Bonjour" -c "greeting"
"""
import argparse
import sys

# Must match TargetLanguage.japaneseRanges in Sources/Konnyaku/PFML3.swift,
# which explains the rule; scripts/check-cli.py compares the two tables.
JAPANESE_RANGES = [
    (0x3005, 0x3007),  # 々 〆 and 〇
    (0x3031, 0x3035),  # Vertical kana iteration marks 〱 to 〵
    (0x303B, 0x303C),  # Vertical kanji iteration mark 〻 and masu mark 〼
    (0x3041, 0x3096),  # Hiragana letters
    (0x309D, 0x309F),  # Hiragana iteration marks ゝ ゞ and digraph ゟ
    (0x30A1, 0x30FA),  # Katakana letters
    (0x30FD, 0x30FF),  # Katakana iteration marks ヽ ヾ and digraph ヿ
    (0x31F0, 0x31FF),  # Katakana Phonetic Extensions (ㇰ)
    (0x3400, 0x4DBF),  # CJK Extension A
    (0x4E00, 0x9FFF),  # CJK Unified Ideographs
    (0xF900, 0xFAFF),  # CJK Compatibility Ideographs (﨑)
    (0xFF66, 0xFF6F),  # Half-width katakana ｦ to ｯ
    (0xFF71, 0xFF9D),  # Half-width katakana ｱ to ﾝ
    (0x1B000, 0x1B16F),  # Kana Supplement to Small Kana Extension (hentaigana)
    (0x20000, 0x3FFFF),  # Ideographic planes: Extension B and later (𠮷)
]


def is_japanese(char):
    code = ord(char)
    return any(start <= code <= end for start, end in JAPANESE_RANGES)


def pick_target(text):
    # ponytail: kana/kanji => en, else => ja; pass -t for anything else
    if any(is_japanese(char) for char in text):
        return "en"
    return "ja"


def parse_glossary(pairs):
    glossary = []
    for pair in pairs:
        source, _, target = pair.partition("=")
        if not source.strip() or not target.strip():
            sys.exit(f"glossary entry must be source=target: {pair!r}")
        glossary.append({"source": source, "target": target})
    return glossary


# Pinned Hugging Face commits: trust_remote_code runs Python from these repos.
MODEL_REVISIONS = {
    "0.8b": "e5fe5b7f26ebaeae48db0ce644b932d1d9b91aaa",
    "2b": "63777ddc6dc80aacacd92a1bf6966105f2f6270c",
    "8b": "9d87684408bdf34500b7d6115c257d83350c1fe5",
    "31b": "e558c8fba45054df70141bc72295024de9b57a44",
}


def main():
    parser = argparse.ArgumentParser(description="Translate with PLaMo 3 Translate")
    parser.add_argument("text", nargs="?", help="text to translate (default: stdin)")
    parser.add_argument("-t", "--to", help="target language code (default: auto ja<->en)")
    parser.add_argument("-s", "--source", help="source language code (default: auto)")
    parser.add_argument("-c", "--context", help="context to disambiguate the text")
    parser.add_argument("-g", "--glossary", action="append", default=[], help="term=translation (repeatable)")
    parser.add_argument("-f", "--form", choices=["plain", "polite"], help="Japanese output style")
    parser.add_argument("-m", "--model", default="8b", choices=list(MODEL_REVISIONS))
    parser.add_argument("--max-tokens", type=int, default=4096)
    args = parser.parse_args()

    text = args.text if args.text is not None else sys.stdin.read()
    text = text.strip()
    if not text:
        parser.error("no text given")

    options = {"target_lang": args.to or pick_target(text)}
    if args.source:
        options["source_lang"] = args.source
    if args.context:
        options["context"] = args.context
    if args.glossary:
        options["glossary"] = parse_glossary(args.glossary)
    if args.form:
        options["form"] = args.form

    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_sampler

    repo = f"pfnet/plamo-3-translate-{args.model}-MLX-4bit"
    model, tokenizer = load(
        repo,
        revision=MODEL_REVISIONS[args.model],
        trust_remote_code=True,
        tokenizer_config={"trust_remote_code": True},
    )
    prompt = tokenizer.apply_chat_template(
        [{"role": "user", "content": text}],
        add_generation_prompt=True,
        tokenize=False,
        **options,
    )
    output = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=args.max_tokens,
        sampler=make_sampler(temp=0),
    )
    print(output.strip())


if __name__ == "__main__":
    main()
