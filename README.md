<div align="center">

**English** | [日本語](README.ja.md)

<img src="assets/logo.png" width="128" height="128" alt="Konnyaku icon">

<h1>Konnyaku</h1>

<p>
  <strong>Fast, private, on-device translation for your Mac menu bar.</strong><br>
  Select text, press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd>, read the translation.<br>
  Powered by PLaMo 3 Translate. Translation runs entirely on your Mac.
</p>

[![Latest release](https://img.shields.io/github/v/release/yukinoda/konnyaku?style=flat-square)](https://github.com/yukinoda/konnyaku/releases/latest)
[![License: MIT](https://img.shields.io/github/license/yukinoda/konnyaku?style=flat-square)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-only-555?style=flat-square)

[Download](../../releases/latest) ·
[Usage](#usage) ·
[FAQ](#faq) ·
[CLI](#cli) ·
[Build from source](#build-from-source)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/popup-dark.png">
  <img src="assets/screenshots/popup-light.png" width="428" alt="The Konnyaku popup translating a Japanese sentence into English">
</picture>

</div>

> [!NOTE]
> Konnyaku is an early release. It is not notarized by Apple, so the first
> launch needs one extra step; see [Install](#install).

## Features

- **On-device.** Runs
  [PLaMo 3 Translate](https://www.preferred.jp/ja/blog/tech/plamo-3-translate-weight-release)
  from Preferred Networks through an embedded llama.cpp. No account, no API
  key; the network is used only to download a model.
- **Works in any app.** Select text and press ⌃⌥T, or use the Services menu.
- **Japanese ⇄ English by default**, plus Chinese, Korean, French, German
  and Spanish as targets.
- **Popup or full editor.** A small popup next to the pointer; ⌘E opens an
  editor that translates as you type.
- **Two model sizes.** Fast 0.8B (573 MB, the default) or higher-quality
  2B (1.8 GB). Only the model you select is downloaded, on first use, and
  verified against a pinned SHA-256.
- **Native.** A SwiftUI menu-bar app with no Python or Homebrew dependency
  at runtime.

## Install

Download `Konnyaku-<version>.dmg` from
[Releases](../../releases), open it,
and drag Konnyaku to Applications. Requires an Apple silicon Mac and
macOS 14 or later.

<a id="upgrading-from-konjac"></a>

> [!IMPORTANT]
> **Upgrading from konjac** (the old name)? Do this before you first open
> Konnyaku:
>
> 1. Quit konjac and delete `konjac.app`. Otherwise only one of the two apps
>    gets ⌃⌥T (the other fails silently) and both show a Services item.
> 2. After launching Konnyaku, allow it under System Settings → Privacy &
>    Security → Accessibility, and remove the old konjac entry. The app
>    identity changed, so macOS treats it as a new app.
>
> Your downloaded models and model-size setting migrate automatically at
> launch. If `~/Library/Application Support/konjac` is still there
> afterwards, you can delete it.

Konnyaku is not signed with an Apple Developer ID or notarized (that needs a
paid Apple Developer account), so macOS blocks the first launch. On macOS 15
(Sequoia) and later the old right-click → Open bypass is gone. Instead:

1. Open Konnyaku once and dismiss the warning.
2. Go to System Settings → Privacy & Security, scroll down, and click
   **Open Anyway** next to Konnyaku.

Or remove the quarantine flag from a terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Konnyaku.app
```

To verify the download, put the published `.sha256` file next to the DMG and
run `shasum -a 256 -c Konnyaku-<version>.dmg.sha256`.

## Usage

**Popup.** Select text in any app and press ⌃⌥T. A small popup shows the
translation next to the pointer. Press ⌃⌥T again to hide it.

**Services.** Select text, then right-click → Services → "Translate with
Konnyaku". The translator opens with the text translated. To give it a
shortcut, use System Settings → Keyboard → Keyboard Shortcuts → Services →
Text → "Translate with Konnyaku".

**Menu bar.** "Translate Clipboard (⌃⌥T)", Open Translator, Settings, About.

| Where | Key | Action |
| --- | --- | --- |
| Anywhere | <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd> | Translate the selection, or hide the Konnyaku window |
| Popup | <kbd>Return</kbd> | Copy the translation and close |
| Popup | <kbd>⌘</kbd><kbd>E</kbd> | Open the full editor |
| Popup, editor | <kbd>Esc</kbd> | Close (clicking elsewhere also closes the popup) |
| Editor | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy the translation |
| Editor | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>R</kbd> | Translate the result again with Auto (ja ↔ en) |

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/editor-dark.png">
    <img src="assets/screenshots/editor-light.png" width="528" alt="The Konnyaku editor translating English into Japanese">
  </picture>
</p>

**Settings** shows the shortcut and the Accessibility status, and lets you
pick or delete models. The selected model downloads the first time you
translate with it.

- The model is downloaded on first use to
  `~/Library/Application Support/Konnyaku/`, from a pinned Hugging Face
  revision. The default is 0.8B.
- RAM: about 0.8 GB for 0.8B and 2.1 GB for 2B while loaded. The model loads
  on the first translation and is unloaded after 5 minutes idle.
- With the model warm, a sentence translates in well under a second.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
    <img src="assets/screenshots/settings-light.png" width="508" alt="Konnyaku Settings with the shortcut, Accessibility status and model list">
  </picture>
</p>

## Privacy and Accessibility

Translation runs entirely on your Mac. The only network access is the model
download from Hugging Face (huggingface.co and its download CDN).

Reading the selection needs the Accessibility permission. Konnyaku asks the
first time; you can also allow it in Settings, which links to System
Settings → Privacy & Security → Accessibility.

Konnyaku reads the selection through Accessibility, or in apps that don't
support that (many browsers), sends ⌘C and puts your clipboard back
afterwards. For that half second the selection is on the clipboard, so
clipboard managers and Universal Clipboard may record it. Copied files from
Finder or Mail come back as names only. Without the permission, copy text
with ⌘C first and ⌃⌥T translates the clipboard.

## FAQ

<details>
<summary><strong>⌃⌥T does nothing</strong></summary>

The ⌃⌥T hotkey is fixed. If it does nothing, another app may already use
that shortcut. Use the Services menu instead.

</details>

<details>
<summary><strong>⌃⌥T translates the clipboard, not my selection (VS Code, Slack)</strong></summary>

Some Electron apps report an empty Accessibility selection even when text is
selected. There ⌃⌥T translates the clipboard instead, so copy first or use
Services.

</details>

<details>
<summary><strong>After updating, Konnyaku asks for Accessibility again</strong></summary>

Konnyaku is ad-hoc signed, so macOS treats each new version as a different
app. After updating, remove Konnyaku from the Accessibility list and allow
it again; Konnyaku asks once more after each update.

</details>

<details>
<summary><strong>Is there a Homebrew cask?</strong></summary>

Not yet. Download the DMG from
[Releases](../../releases).

</details>

<details>
<summary><strong>Upgrading from konjac</strong></summary>

See [Upgrading from konjac](#upgrading-from-konjac) under Install.

</details>

## CLI

A Python command-line version for scripts and the terminal. Requirements: an
Apple silicon Mac and [uv](https://docs.astral.sh/uv/).

```bash
./konnyaku.py "会議は来週の月曜日に変更されました。"
# The meeting has been rescheduled for next Monday.

echo "This system is convenient." | ./konnyaku.py -f plain
# このシステムは便利だ。

./konnyaku.py -t fr "Good morning, everyone."
# Bonjour à tous.
```

<details>
<summary>Options</summary>

| Option | Meaning |
| --- | --- |
| `-t LANG` | Target language code (default: Japanese text → `en`, anything else → `ja`) |
| `-s LANG` | Source language code (default: auto-detect) |
| `-c TEXT` | Context to disambiguate the source text |
| `-g SRC=DST` | Glossary entry (repeatable) |
| `-f plain\|polite` | Japanese output style |
| `-m SIZE` | Model size: `0.8b`, `2b`, `8b` (default), `31b` |

</details>

Unlike the app, whose default is 0.8B, the CLI's `-m` defaults to `8b`, so
the first run downloads that model (several GB). Pass `-m 0.8b` for the small
one. The model is downloaded from Hugging Face on first run. The CLI reloads the
model on every call, so expect a few seconds per invocation. Model revisions
are pinned to specific Hugging Face commits (see `MODEL_REVISIONS` in
`konnyaku.py`).

## Build from source

Requirements: macOS 14+ and Xcode with Swift 5.9 or later (CI uses
Xcode 16.4).

```bash
./scripts/build-app.sh
open build/Konnyaku.app
```

`./scripts/make-dmg.sh` builds `build/Konnyaku-<version>.dmg` and its
`.sha256` (set `KONNYAKU_VERSION`, e.g. `1.2.3`; default `0.0.0`).

`swift test` runs the unit tests (prompt builder and target-language picker).

The app embeds llama.cpp as a prebuilt XCFramework, pinned in
`Package.swift`.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) to build, test and send a pull
request, and [SECURITY.md](SECURITY.md) to report a vulnerability privately.
Everyone taking part agrees to the [code of conduct](CODE_OF_CONDUCT.md).

## Acknowledgements

- [PLaMo 3 Translate](https://www.preferred.jp/ja/blog/tech/plamo-3-translate-weight-release)
  by Preferred Networks, the model that does the translating.
- [llama.cpp](https://github.com/ggml-org/llama.cpp), which runs it on
  Apple silicon.

The name: konnyaku (konjac jelly) is a nod to the classic "translation
konjac" idea from Japanese pop culture.

## License

Konnyaku's own code is MIT-licensed (see [LICENSE](LICENSE)). The app
bundles llama.cpp (MIT); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Built with PLaMo. The PLaMo 3 Translate model weights are **not** part of
this repository: Konnyaku downloads them from Preferred Networks'
repositories on Hugging Face. Preferred Networks licenses them under the
[PLaMo Community License](https://plamo.preferredai.jp/info/plamo-community-license-en).
By using Konnyaku you use the model and agree to that license. Read it in
full; in particular:

- Personal and academic use needs no registration. Any other use counts as
  commercial, including use at work or inside an organisation.
- Commercial use requires
  [registering with Preferred Networks](https://forms.gle/mTL8tBLrMYXKNZD56)
  first, and is allowed only if you (or your affiliated company) have annual
  revenue of 1 billion yen or less. Otherwise you need a separate commercial
  license from Preferred Networks.
- If you publish translations, say they were produced by PLaMo.
- You must be 18 or older, or have reached the age of legal capacity in your
  country, or have a guardian's consent.

This list is a summary for reference; the license text is what applies.
