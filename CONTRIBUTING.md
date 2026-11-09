# Contributing to Konnyaku

Thanks for helping. Konnyaku has one maintainer, so small, focused pull requests
get reviewed fastest. For anything larger than a bug fix, open an issue first
so we can agree on the approach.

## Build and test

You need an Apple silicon Mac with macOS 14+ and Xcode with Swift 5.9 or
later (the `swift-tools-version`). CI uses Xcode 16.4 (Swift 6.1).

```bash
swift test                 # unit tests
./scripts/build-app.sh     # build/Konnyaku.app, ad-hoc signed
open build/Konnyaku.app
```

`./scripts/make-dmg.sh` builds the release DMG and its `.sha256`.

The CLI is a single [uv](https://docs.astral.sh/uv/) script:
`./konnyaku.py "text"`. uv installs its dependencies on first run. They are
pinned with `==` in the script header, so bump them by hand (Dependabot does
not cover them) and check that `load` still accepts the arguments the script
passes.

Model weights are downloaded at runtime and are never committed
(`.gitignore` blocks `*.gguf` and `*.safetensors`).

## Pull requests

1. Branch from `main` and keep each PR to one concern.
2. Run `swift test` and `./scripts/build-app.sh` before pushing. CI runs both,
   plus a gitleaks secret scan.
3. Describe what changed, why, and how you tested it. The PR template lists
   what to fill in.
4. UI changes: include a screenshot or a short recording.
5. Docs: README.md and README.ja.md cover the same content; update both.

The maintainer reviews with `/code-review` (Claude Code) and Codex in
addition to reading the diff, so expect some automated review comments.

## Code style

Code must be easy to read, in Swift, Python, shell and YAML alike:

- One statement per line. No compressed one-liners or multi-statement lines.
- Split long expressions into named locals and long conditions into separate
  checks.
- Comments explain why, not what.
- Match the surrounding code; there is no formatter config yet.

## Secret scanning

CI runs gitleaks on every pull request and every push to `main`. Each run
scans all history reachable from the commit under test: for a pull request,
its own commits plus `main` up to where the branch started.

If the scan flags something:

- A real secret in a pull request: revoke or rotate it, then rewrite the
  branch so the secret never reaches `main` (amend or rebase the commit that
  added it, then force-push the branch).
- A false positive in a pull request: add a `gitleaks:allow` comment to that
  line in the commit that introduced it (amend or rebase that commit). A
  follow-up commit is not enough, because every commit's change is scanned.
  Don't use a fingerprint here: fingerprints include the commit SHA, which
  any rebase, squash, amend or rebase-merge changes. For files that can't
  hold a comment (e.g. JSON fixtures), add a path or regex allowlist to a
  `.gitleaks.toml` at the repo root instead.
- A finding already on `main` (a rotated secret or a false positive): rotate
  it if it is real, then add its fingerprint (printed in the job log of a push
  to `main`) to a `.gitleaksignore` file at the repo root. Open pull requests
  pick up the new ignore entry once they are rebased onto `main`.

## Releases

The maintainer pushes a `v*` tag on a commit already on `main`;
`.github/workflows/release.yml` builds the ad-hoc-signed DMG and publishes a
GitHub Release. Its notes are generated from merged PRs and grouped by label
(the release-notes config, `.github/release.yml`), so the maintainer labels each
PR before merging; `ignore-for-release` leaves a PR out.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
