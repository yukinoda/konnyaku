# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the
[Security tab](https://github.com/yukinoda/konnyaku/security) and click
**Report a vulnerability**. Don't open a public issue.

Konnyaku has one maintainer working on it in spare time. Expect an
acknowledgement within a week. Fixes ship in a new release, and the advisory
is published once the release is out.

Only the latest release is supported.

## In scope

- **Model download integrity.** The app downloads GGUF weights from a pinned
  Hugging Face revision and checks them against a pinned SHA-256 once, before
  saving them to the models folder (`Sources/Konnyaku/ModelStore.swift`).
  Saved files are not checked again. A way to make Konnyaku save or load a
  file that did not pass that check is in scope, except changes made by you or
  by a process running as you (see Out of scope). The CLI (`konnyaku.py`) runs
  model code with `trust_remote_code`, pinned to specific commits; bypassing
  that pin is in scope too.
- **Clipboard and Accessibility handling.** With the Accessibility permission,
  the translate shortcut (⌃⌥T by default) reads the selected text in the
  frontmost app, through Accessibility or, where that doesn't work, by
  sending ⌘C and putting the previous clipboard back
  (`Sources/Konnyaku/SelectionReader.swift`); otherwise it reads the
  clipboard. Clipboard reads, including the ⌘C fallback, skip items that
  password managers and other apps mark as concealed, transient or
  auto-generated. The Accessibility read and the "Translate with Konnyaku"
  service, which the user invokes on their own selection, don't apply that
  filter. Leaking clipboard or selected text off the Mac, into logs, or into
  another app is in scope, as is misuse of the Accessibility permission.
- **Prompt handling.** User text must not be able to inject PLaMo special
  tokens into the prompt (`Sources/Konnyaku/PFML3.swift`).
- **Release pipeline.** `.github/workflows/release.yml`, the build scripts in
  `scripts/`, and the published DMG, `.sha256` and build attestation: for
  example a way to get a tampered DMG released or attested, or to leak the
  workflow token.

## Out of scope

- Gatekeeper warnings. Releases are ad-hoc signed and not notarized, because
  the project has no paid Apple Developer account. This is documented in the
  README.
- Known limits of the ⌘C fallback, documented in the README: until Konnyaku
  reads the copy (at most about half a second), the selection is on the
  clipboard, where clipboard managers and Universal Clipboard can record it.
  Konnyaku can't tell which app wrote to the clipboard, so another write in
  that window may be taken as the selection, translated, and replaced. If the
  app copies after the wait, the selection stays on the clipboard, the
  previous clipboard is not restored, and a later press of the shortcut or
  Translate Clipboard may translate it.
- Changes to files in the models folder made outside Konnyaku, by you or by a
  process running as you. Such a process can already do far worse.
- Translation quality, or harmful text the model produces. Report those to
  Preferred Networks, who publish PLaMo.
- Vulnerabilities in llama.cpp itself. Report those
  [upstream](https://github.com/ggml-org/llama.cpp/security); Konnyaku will
  update its pinned build once a fix is released.
