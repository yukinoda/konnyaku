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

### Install

Download `konjac-<version>.dmg` from the
[Releases](../../releases) page, open it, and drag konjac to Applications.
Apple silicon Macs only, macOS 14+.

konjac is not signed with an Apple Developer ID or notarized (that needs a paid
Apple Developer account), so macOS blocks the first launch. On macOS 15
(Sequoia) and later the old right-click → Open bypass is gone. Instead:

1. Open konjac once and dismiss the warning.
2. Go to System Settings → Privacy & Security, scroll down, and click
   **Open Anyway** next to konjac.

Or remove the quarantine flag from a terminal:

```bash
xattr -dr com.apple.quarantine /Applications/konjac.app
```

To verify the download, put the published `.sha256` file next to the DMG and run
`shasum -a 256 -c konjac-<version>.dmg.sha256`.

### Translate from any app

- Select text in any app, then right-click, Services, "Translate with konjac".
  The floating translator opens with the text translated. To add a shortcut,
  use System Settings, Keyboard, Keyboard Shortcuts, Services, Text,
  "Translate with konjac".
- Or copy text with ⌘C and press ⌃⌥T to translate the clipboard. Press ⌃⌥T
  again to hide the panel.
- Esc closes the panel. No Accessibility permission is needed.
- The ⌃⌥T hotkey is fixed. If it does nothing, another app may already use
  that shortcut. Use the Services menu instead.

## Build from source

Requirements: macOS 14+ and Xcode (Swift 5.9+).

```bash
./scripts/build-app.sh
open build/konjac.app
```

`./scripts/make-dmg.sh` builds `build/konjac-<version>.dmg` and its `.sha256`
(set `KONJAC_VERSION`, e.g. `1.2.3`; default `0.0.0`).

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
Model revisions are pinned to specific Hugging Face commits (see `MODEL_REVISIONS` in `konjac.py`).

## Security

CI runs gitleaks secret scanning over the full history of every pull request
and every push to `main`.

If the scan flags something:

- A real secret: revoke or rotate it first. Rotating does not remove it from
  git history, so the scan keeps flagging it until it is ignored (below).
- A false positive in a pull request: add a `gitleaks:allow` comment to that
  line in the commit that introduced it (amend or rebase that commit). A
  follow-up commit is not enough, because every commit's change is scanned.
  Don't use a fingerprint here: fingerprints include the commit SHA, which
  any rebase, squash, amend or rebase-merge changes.
- A finding already on `main` (false positive or rotated secret): add the
  finding's fingerprint (printed in the job log) to a `.gitleaksignore` file
  at the repo root.

## Model license

konjac's own code is MIT-licensed (see [LICENSE](LICENSE)). The PLaMo 3
Translate model weights are **not** part of this repository and are
distributed by Preferred Networks under the
[PLaMo Community License](https://plamo.preferredai.jp/info/plamo-community-license-en).
Read it before using the model, especially for commercial use.
