# konjac

Fast, private, on-device translation for macOS, powered by
[PLaMo 3 Translate](https://www.preferred.jp/ja/blog/tech/plamo-3-translate-weight-release)
from Preferred Networks. Everything runs locally; no text leaves your Mac.

> Status: early prototype. A command-line tool and a first version of the
> native menu-bar app are available.

## App

A menu-bar app that translates as you type. It embeds llama.cpp (prebuilt
XCFramework, pinned in `Package.swift`), so there is no Python or Homebrew
dependency at runtime.

Requirements: macOS 14+ and Xcode (Swift 5.9+).

```bash
./scripts/build-app.sh
open build/konjac.app
```

`swift test` runs the unit tests (prompt builder and target-language picker).

- The model is downloaded on first use to
  `~/Library/Application Support/konjac/`, from a pinned Hugging Face
  revision, and verified against a pinned SHA-256. Default is the 0.8B model
  (573 MB); the popover can switch to the 2B model (1.8 GB) for higher quality.
- RAM: about 0.8 GB for 0.8B and 2.1 GB for 2B while loaded. The model loads
  on the first translation and is unloaded after 5 minutes idle.
- With the model warm, a sentence translates in well under a second.

## CLI

Requirements: an Apple silicon Mac and [uv](https://docs.astral.sh/uv/).

```bash
./konjac.py "会議は来週の月曜日に変更されました。"
# The meeting has been rescheduled for next Monday.

echo "This system is convenient." | ./konjac.py -f plain
# このシステムは便利だ。

./konjac.py -t fr "Good morning, everyone."
# Bonjour à tous.
```

| Option | Meaning |
| --- | --- |
| `-t LANG` | Target language code (default: Japanese text → `en`, anything else → `ja`) |
| `-s LANG` | Source language code (default: auto-detect) |
| `-c TEXT` | Context to disambiguate the source text |
| `-g SRC=DST` | Glossary entry (repeatable) |
| `-f plain\|polite` | Japanese output style |
| `-m SIZE` | Model size: `0.8b`, `2b`, `8b` (default), `31b` |

The model is downloaded from Hugging Face on first run. The CLI reloads the
model on every call, so expect a few seconds per invocation.

## Model license

konjac's own code is MIT-licensed (see [LICENSE](LICENSE)). The PLaMo 3
Translate model weights are **not** part of this repository and are
distributed by Preferred Networks under the
[PLaMo Community License](https://plamo.preferredai.jp/info/plamo-community-license-en).
Read it before using the model, especially for commercial use.
