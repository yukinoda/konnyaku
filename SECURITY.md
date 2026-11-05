# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the
[Security tab](https://github.com/yukinoda/konjac/security) and click
**Report a vulnerability**. Don't open a public issue.

konjac has one maintainer working on it in spare time. Expect an
acknowledgement within a week. Fixes ship in a new release, and the advisory
is published once the release is out.

Only the latest release is supported.

## In scope

- **Model download integrity.** The app downloads GGUF weights from a pinned
  Hugging Face revision and checks them against a pinned SHA-256 before use
  (`Sources/Konjac/ModelStore.swift`). A way to make konjac load a file that
  did not pass that check is in scope. The CLI (`konjac.py`) runs model code
  with `trust_remote_code`, pinned to specific commits; bypassing that pin is
  in scope too.
- **Clipboard and Accessibility handling.** konjac reads the clipboard on
  ⌃⌥T and skips items that password managers mark as concealed or transient.
  Leaking clipboard or selected text off the Mac, into logs, or into another
  app is in scope, as is misuse of the Accessibility permission.
- **Prompt handling.** User text must not be able to inject PLaMo special
  tokens into the prompt (`Sources/Konjac/PFML3.swift`).
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
  [upstream](https://github.com/ggml-org/llama.cpp/security); konjac will
  update its pinned build once a fix is released.
