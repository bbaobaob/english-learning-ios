# Pull request

Keep it small and focused — one concern per PR. This repository is a SwiftUI app plus two Swift
packages, so a PR that spans all three usually means it should be three PRs.

## Before you open it

```sh
make project          # regenerate after any project.yml / Package.swift / App/ change
make test             # EnglishCore (Linux-portable) + EnglishStore (SwiftData)
make validate-content # if you touched Packages/EnglishCore/Resources/content
```

- [ ] `make test` passes locally.
- [ ] `make validate-content` passes, if content changed.
- [ ] `EnglishLearning.xcodeproj` is **not** in the diff. It is generated from `project.yml` and
      gitignored. If it appears, run `make clean` and check `.gitignore`.
- [ ] No secrets, signing material, or `Package.resolved` churn in the diff.
- [ ] `docs/ARCHITECTURE.md` is unchanged. It is a frozen contract: if your change requires a new
      public type, a renamed type, or a changed signature, say so in the description and get it
      agreed **before** writing the code. Do not edit the contract in the same PR that violates it.
- [ ] `App/` contains no business logic: no grading, no streak math, no date math, no direct
      `ModelContext` access outside Views/Store. That belongs in `EnglishCore` / `EnglishStore`.

## Description

- **What changed** and **why** — the user-visible reason, not a restatement of the diff.
- **Which package(s)**: `App`, `Packages/EnglishCore`, `Packages/EnglishStore`.
- **New public API**, if any, with the exact signature.
- **Content changes**: list the added/changed topic, lesson and exercise ids, and confirm the
  per-topic minimums in `docs/ARCHITECTURE.md` §3 (≥8 exercises across ≥6 kinds, ≥2 dictation).
- **Screenshots or a screen recording** for any UI change. Dark mode included.
- **How you verified it**, beyond the test suite — which device/simulator, which flows you walked.

## Content PRs

- Stable kebab-case ids. Never reuse or renumber an existing id: SwiftData rows key off them and
  renamed ids orphan user progress.
- No invented or placeholder English, no dead URLs, no emoji in content text. A `VideoClip` with
  `source.type == "none"` is a valid, complete state — prefer it over a link you cannot verify.
- Vocabulary needs an IPA transcription, a Vietnamese meaning, and a speech `AudioClip`.

## Screenshots

`App/Screenshots/01-home.png` … keep them small (max 1280px wide) and in the order the README shows
them. Do not commit simulator clutter, debug overlays or untranslated strings.
