#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["mlx-lm", "mlx", "transformers", "numba"]
# ///
"""konjac: local translation with PLaMo 3 Translate (MLX, Apple silicon).

  konjac "会議は来週の月曜日に変更されました。"     # ja -> en (auto)
  echo "This system is convenient." | konjac       # non-ja -> ja (auto)
  konjac -t fr "Hello" -g "Hello=Bonjour" -c "greeting"
"""
import argparse
import re
import sys

JAPANESE = re.compile(r"[぀-ヿ一-鿿]")


def pick_target(text):
    # ponytail: kana/kanji => en, else => ja; pass -t for anything else
    if JAPANESE.search(text):
        return "en"
    return "ja"


def parse_glossary(pairs):
    glossary = []
    for pair in pairs:
        source, _, target = pair.partition("=")
        if not target:
            sys.exit(f"glossary entry must be source=target: {pair!r}")
        glossary.append({"source": source, "target": target})
    return glossary


def main():
    parser = argparse.ArgumentParser(description="Translate with PLaMo 3 Translate")
    parser.add_argument("text", nargs="?", help="text to translate (default: stdin)")
    parser.add_argument("-t", "--to", help="target language code (default: auto ja<->en)")
    parser.add_argument("-s", "--source", help="source language code (default: auto)")
    parser.add_argument("-c", "--context", help="context to disambiguate the text")
    parser.add_argument("-g", "--glossary", action="append", default=[], help="term=translation (repeatable)")
    parser.add_argument("-f", "--form", choices=["plain", "polite"], help="Japanese output style")
    parser.add_argument("-m", "--model", default="8b", choices=["0.8b", "2b", "8b", "31b"])
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
