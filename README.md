# konjac

Fast, private, on-device translation for macOS, powered by
[PLaMo 3 Translate](https://www.preferred.jp/ja/blog/tech/plamo-3-translate-weight-release)
from Preferred Networks. Everything runs locally; no text leaves your Mac.

> Status: early prototype. A command-line tool is available now; a native
> menu-bar app is in progress.

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
