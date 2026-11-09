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
  Hugging Face revision and checks them against a pinned SHA-256 once, after
  the download and before saving them to the models folder
  (`Sources/Konnyaku/ModelStore.swift`). A saved file is not checked again
  when it is loaded. A way to get a download that fails the check saved to
  the models folder is in scope. The CLI (`konnyaku.py`) runs model code with
  `trust_remote_code`, pinned to specific commits; bypassing that pin is in
  scope too.
- **Clipboard and Accessibility handling.** When Konnyaku has the
  Accessibility permission and is not the frontmost app, ⌃⌥T reads the
  selection through Accessibility or, where that isn't supported, sends ⌘C
  and then puts the previous clipboard back. Otherwise, or with nothing
  selected, ⌃⌥T reads only the clipboard, as do the Translate Clipboard and
  Open Translator menu items. These clipboard reads ignore items that
  password managers and other apps mark as concealed, transient or
  auto-generated. ⌘C is not sent while the clipboard holds such an item, and
  a copied selection marked that way is not translated; the previous
  clipboard is put back. The "Translate with Konnyaku" service translates
  the selection the user explicitly sends it, without that filter. Leaking
  clipboard or selected text off the Mac, into logs, or into another app is
  in scope, as is misuse of the Accessibility permission.
- **Prompt handling.** User text must not be able to inject PLaMo special
  tokens into the prompt (`Sources/Konnyaku/PFML3.swift`).
- **Release pipeline.** `.github/workflows/release.yml`, the build scripts in
  `scripts/`, and the published DMG and `.sha256`: for example a way to get a
  tampered DMG released or to leak the workflow token.

## Out of scope

- Gatekeeper warnings. Releases are ad-hoc signed and not notarized, because
  the project has no paid Apple Developer account. This is documented in the
  README.
- Clipboard managers or Universal Clipboard recording the selection that
  the ⌘C fallback puts on the clipboard (see the README's Privacy and
  Accessibility section). Konnyaku waits about half a second for the copy;
  a copy that lands later is not restored and stays on the clipboard.
- Tampering with saved model files by a process already running as your
  user. Such a process can already do far worse, and Konnyaku checks each
  file once, when it is downloaded.
- Translation quality, or harmful text the model produces. Report those to
  Preferred Networks, who publish PLaMo.
- Vulnerabilities in llama.cpp itself. Report those
  [upstream](https://github.com/ggml-org/llama.cpp/security); Konnyaku will
  update its pinned build once a fix is released.
