# English Learning

A native SwiftUI English-learning app that works entirely offline: grammar curriculum, dictation, vocabulary with spaced repetition, IELTS practice and progress tracking.

```
┌─────────────────────────────────────────────┐
│                                             │
│   Screenshot: Home dashboard                │
│   (add Assets/Screenshots/home.png and      │
│    reference it here)                       │
│                                             │
└─────────────────────────────────────────────┘
```

## Features

- **Home dashboard** — resume point, daily XP goal, streak, review queue count.
- **19-topic grammar curriculum** — alphabet + 18 grammar topics, beginner → advanced.
- **Alphabet listening mode** — letter/sound drills with speech synthesis.
- **Dictation engine** — LCS word-level diffing, accuracy score, "should be" hints.
- **Vocabulary with spaced repetition** — SM-2 lite scheduling, due queue, favourites.
- **IELTS modules** — listening, reading, writing, speaking.
- **Four skills** — reading, listening, writing, speaking practice.
- **Teaching methods** — per-topic method notes alongside the theory.
- **Streaks, XP and achievements** — daily goal, streak bonus, 12+ achievement catalogue.
- **Notifications** — daily reminder, review, listening, IELTS, streak protection.
- **Offline** — all content is bundled JSON; audio is on-device TTS. No network calls.

## Requirements

- Xcode 16+ (Swift 5.10, iOS 17 SDK)
- macOS 14+ to build
- iOS 17+ to run
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38+ for local project generation

## Quick start

```sh
brew install xcodegen
make project
open EnglishLearning.xcodeproj
```

`EnglishLearning.xcodeproj` is **generated** from `project.yml` and is not in git. Never edit it
in Xcode — re-run `make project` after changing `project.yml`, the packages, or `App/`.

## Project layout

```
Packages/EnglishCore/     Foundation only. Content models, engine, session,
                          review, progress, media protocols. Portable.
Packages/EnglishStore/    SwiftData. @Model schemas + ProgressStore facade.
App/                      SwiftUI app target. No business logic.
docs/ARCHITECTURE.md      Frozen contract: layout, content schema, API.
docs/BUILD.md             Build and unsigned-IPA runbook.
project.yml               XcodeGen spec (the only project source of truth).
```

Dependency direction: `App → EnglishStore → EnglishCore`, never the reverse.

## Testing

```sh
make test          # both packages
make test-core     # EnglishCore only
make test-store    # EnglishStore only (needs macOS 14+)
```

`EnglishCore` is Foundation-only, so its tests run in seconds on Linux in CI — grading,
dictation, spaced repetition, streaks, XP and achievements are all provable without a device.

Content is validated too: `make validate-content` parses every JSON file under
`Packages/EnglishCore/Resources/content` and checks the 19 topic ids resolve to files.

## GitHub Actions

| Workflow | Trigger | What it does | Artifacts |
| --- | --- | --- | --- |
| `CI` | push, PR, manual | `test-core` (Linux), `test-store` (macOS), `lint-content` (JSON validation), `build-app` (generates the project and compiles the app for the simulator) | none |
| `Unsigned IPA` | manual, tag `v*`, push to `main` | Archives without a code signature and zips the `.app` into an unsigned IPA | `EnglishLearning-unsigned-ipa`, `EnglishLearning-xcarchive`, GitHub Release on tags |

All jobs run with `contents: read` and are cancelled when superseded.

## IPA installation

This project ships **unsigned** — no Apple Developer membership, no credentials, no code signature.
That is a deliberate trade: anyone can build it, and anyone can run it, but **iOS cannot install an
unsigned IPA on a stock device.** You need a re-signing tool that injects your own identity.

**Get the IPA**

- Actions → `Unsigned IPA` → pick a run → download the `EnglishLearning-unsigned-ipa` artifact.
- On a `v*` tag, the same file is attached to the GitHub Release.

**Install it** — requirements: **iOS 17.0 or newer**, an iPhone or iPad, and one of:

| Tool | Needs | Free Apple account limit |
| --- | --- | --- |
| **Sideloadly** | Windows/macOS, Apple ID + password | 3 apps, re-sign every 7 days |
| **AltStore** | macOS, or on-device with AltStore | 3 apps, refreshed every 7 days |
| **TrollStore** | A TrollStore-compatible iOS version | No expiry, no limit |

With Sideloadly: connect by USB, drag the `.ipa` onto the window, enter the Apple ID, Start. If iOS
shows an untrusted-developer prompt, go to Settings → General → VPN & Device Management and trust
the profile. With a free Apple ID the profile expires after 7 days — re-run the sideload to refresh.

**Prefer the simulator?** Build and run locally with no signing step at all: `make project`, then
`open EnglishLearning.xcodeproj` and hit Run. That path needs no account and no IPA.

Full instructions: **[docs/BUILD.md](docs/BUILD.md)**.

## Content authoring

All content lives as JSON under `Packages/EnglishCore/Resources/content`: `content.json` is the
index, `topics/<topic-id>.json` holds the 19 topics, plus `vocabulary.json` and `ielts.json`. Adding
a lesson means adding a `lessons` entry to the right topic file — no code changes, the library globs
the directory. The exact schema, the tagged-union `LessonStep` shapes, and the content rules (stable
kebab-case ids, no dead URLs, minimum 8 exercises per grammar topic across 6+ kinds) are in
**[docs/ARCHITECTURE.md §1 and §3](docs/ARCHITECTURE.md)**.

## Architecture

`docs/ARCHITECTURE.md` is the frozen contract: module layout (§0), content JSON schema (§1), exact
public API signatures (§2), content rules (§3) and required test coverage (§4). Change requests go
there, not around it.

## License

MIT — Copyright (c) 2026 Mai Bao. See [LICENSE](LICENSE).
