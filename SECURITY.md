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
  when it is loaded. A way to get a download that did not pass the check
  saved or loaded is in scope. The CLI (`konnyaku.py`) runs model code
  with `trust_remote_code`, pinned to specific commits; bypassing that pin is
  in scope too.
- **Clipboard and Accessibility handling.** Konnyaku reads the clipboard on
  ⌃⌥T and skips items that password managers mark as concealed, transient
  or auto-generated.
  Leaking clipboard or selected text off the Mac, into logs, or into another
  app is in scope, as is misuse of the Accessibility permission.
- **Prompt handling.** User text must not be able to inject PLaMo special
  tokens into the prompt (`Sources/Konnyaku/PFML3.swift`).
- **Release pipeline.** `.github/workflows/release.yml`, the build scripts in
  `scripts/`, and the published DMG and `.sha256`: for example a way to get a
  tampered DMG released or to leak the workflow token.

## Out of scope

- Gatekeeper warnings. Releases are ad-hoc signed and not notarized, because
  the project has no paid Apple Developer account. This is documented in the
  README.
- Translation quality, or harmful text the model produces. Report those to
  Preferred Networks, who publish PLaMo.
- Vulnerabilities in llama.cpp itself. Report those
  [upstream](https://github.com/ggml-org/llama.cpp/security); Konnyaku will
  update its pinned build once a fix is released.
