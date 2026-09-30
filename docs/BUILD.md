# Build and Unsigned IPA Runbook

For a developer who has never seen this repository. Everything below assumes a Mac with Xcode 16
and a shell in the repository root.

This project ships an **unsigned** IPA. There is no Apple Developer account, no team, no
certificate, no provisioning profile and no App Store Connect record anywhere in this repository.
Building, testing and running in the simulator never needs a credential.

- [1. Local setup](#1-local-setup)
- [2. Generating the Xcode project](#2-generating-the-xcode-project)
- [3. Running tests](#3-running-tests)
- [4. Validating content](#4-validating-content)
- [5. The generated project is generated](#5-the-generated-project-is-generated)
- [6. Continuous integration](#6-continuous-integration)
- [7. Unsigned IPA — the shipped artifact](#7-unsigned-ipa--the-shipped-artifact)
- [8. Troubleshooting](#8-troubleshooting)

---

## 1. Local setup

Install:

1. Xcode 16 or newer (App Store or developer.apple.com/download).
   Verify: `xcodebuild -version` → `Xcode 16.x`.
2. The command line tools: `xcode-select --install`.
3. XcodeGen 2.38 or newer: `brew install xcodegen`. Verify: `xcodegen --version`.
4. Python 3 (for the content validator): `python3 --version`. macOS ships it as part of the
   Command Line Tools.

The engine packages build with the Swift 5.10 language mode and target iOS 17 / macOS 14.

```sh
git clone <repo-url>
cd Small-APP
brew install xcodegen
make project
```

---

## 2. Generating the Xcode project

`project.yml` is the only source of truth for the project layout. XcodeGen turns it into
`EnglishLearning.xcodeproj`:

```sh
make project          # == xcodegen generate
```

Re-run this command whenever you change any of:

- `project.yml` itself (targets, settings, Info.plist keys, schemes)
- `Packages/**/Package.swift` (added/removed products, new dependencies)
- the folder layout under `App/`

Do not open the generated project and hand-edit build settings. Those edits live in the pbxproj and
are destroyed by the next `make project`. Change `project.yml` instead.

**What the spec defines**

| Setting | Value |
| --- | --- |
| Project / product name | `EnglishLearning` |
| Bundle identifier | `com.b.english` |
| Display name | English Learning |
| Marketing version | 1.0.0 |
| Build number | 1 |
| Deployment target | iOS 17.0 |
| Swift language mode | 5.10 |
| Strict concurrency | `minimal` |
| User script sandboxing | `ENABLE_USER_SCRIPT_SANDBOXING = YES` |
| Code signature | None. The project declares no team and no profile; every build path here passes `CODE_SIGNING_ALLOWED=NO`. |
| Schemes | `EnglishLearning` (build/run/archive), `EnglishCore` (runs the package tests) |

`App/Info.plist` is generated from the `info:` block in `project.yml` and is gitignored. Adding a
usage description means editing `project.yml`, not the plist.

**Schemes**

- `EnglishLearning` — build, run and archive the app.
- `EnglishCore` — build and test the portable engine package on its own, without the app target.
  This is the fast inner loop for grading, dictation, SRS, streak and XP work.

---

## 3. Running tests

```sh
make test          # EnglishCore + EnglishStore
make test-core     # Foundation-only engine, seconds
make test-store    # SwiftData persistence, needs macOS 14+
```

Or from Xcode: `⌘U` with the `EnglishCore` scheme active, or
`swift test --package-path Packages/EnglishCore`.

`Packages/EnglishCore` imports Foundation only — no SwiftUI, no SwiftData, no AVFoundation — which
is exactly why it is a separate package. It compiles and tests on Linux in CI. If a change to the
engine cannot be tested there without a device or simulator, the design has drifted; see
`docs/ARCHITECTURE.md` §0.

---

## 4. Validating content

All content is JSON under `Packages/EnglishCore/Resources/content`. A malformed file is a runtime
failure on a device, not a compile error, so it gets its own check:

```sh
make validate-content
```

It parses every `.json` file, rejects empty files, and asserts that `content.json` lists exactly 19
topic ids, that they are unique, and that each has a matching `topics/<id>.json`. The same script
runs in the `lint-content` CI job. Required test coverage is in `docs/ARCHITECTURE.md` §4.

---

## 5. The generated project is generated

`EnglishLearning.xcodeproj`, `App/Info.plist`, `.build/`, `build/`, `*.xcarchive` and `*.ipa` are
all ignored by git. This is deliberate:

- A committed pbxproj produces a merge conflict on almost every generate, and the conflict is always
  resolved by taking someone's machine-specific state.
- Xcode writes `xcuserdata/` (per-user breakpoints, window layout, device lists) into the project,
  which is noise in review and can leak local paths.
- The generated file drifts silently from `project.yml`, so nobody knows which one is authoritative.

If a pbxproj change is genuinely needed, it belongs in `project.yml`. There is no exception.

---

## 6. Continuous integration

### `CI` (`.github/workflows/ci.yml`)

Triggers: every push to `main`, every pull request, manual dispatch.

| Job | Runner | What it proves |
| --- | --- | --- |
| `test-core` | ubuntu-latest, Swift 5.10 | The engine compiles and passes its suite on Linux. |
| `test-store` | macos-latest | SwiftData persistence works on Darwin. |
| `lint-content` | ubuntu-latest | Content JSON is valid and complete. |
| `build-app` | macos-latest | The real project generates and the app compiles for the simulator. |

`permissions: contents: read` everywhere. A `concurrency` group per ref cancels superseded runs, so
pushing twice does not queue two builds.

### `Unsigned IPA` (`.github/workflows/unsigned-ipa.yml`)

Manual dispatch (with a `configuration` input), every `v*` tag, and every push to `main`. Archives
with signing disabled, zips `Payload/EnglishLearning.app` into an unsigned IPA, uploads the IPA and
the `.xcarchive` as artifacts, and attaches the IPA to a GitHub Release when the trigger is a tag.
SPM resolution and DerivedData are cached on the `Package.resolved` + `project.yml` hash.

---

## 7. Unsigned IPA — the shipped artifact

This is the release path. No Apple Developer membership, no credentials, nothing to configure.

**Trigger:** Actions → `Unsigned IPA` → Run workflow, or push a tag (`git tag v1.0.0 && git push
origin v1.0.0`) to get a GitHub Release with the IPA attached. Pushes to `main` also produce it as a
workflow artifact.

**What CI does**

```sh
xcodegen generate
xcodebuild -project EnglishLearning.xcodeproj -scheme EnglishLearning \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/EnglishLearning.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SKIP_INSTALL=NO archive
mkdir -p build/Payload
cp -R build/EnglishLearning.xcarchive/Products/Release-iphoneos/EnglishLearning.app build/Payload/
(cd build && zip -qry EnglishLearning-unsigned.ipa Payload)
```

`SKIP_INSTALL=NO` matters: with the default (`SKIP_INSTALL=YES`) the `.app` is stripped out of the
archive and there is nothing to package.

**Local equivalent:** `make archive-unsigned` produces the same archive without packaging the IPA.

### Getting the artifact

- **Actions run:** open the `Unsigned IPA` run, scroll to *Artifacts* at the bottom, download
  `EnglishLearning-unsigned-ipa` and unzip it to get `EnglishLearning-unsigned.ipa`.
- **Tag / release:** open the GitHub Release for the `v*` tag and download the attached asset of the
  same name.

If neither exists, the workflow did not run on that commit — see §8.

### Installing it — read this before you try

**An unsigned IPA cannot be installed directly on a stock device.** That is not a bug in the build;
it is the consequence of there being no signature. The binary has no embedded provisioning profile
and no valid code signature, so iOS refuses to launch it. A re-signing tool injects your own
identity and profile at install time. This is the expected limitation of a build with no
credentials.

| Tool | Needs | Free Apple account limit |
| --- | --- | --- |
| **Sideloadly** | Windows or macOS, Apple ID + password | 3 apps, re-sign every 7 days |
| **AltStore** | macOS (or on-device with AltStore) | 3 apps, refreshed every 7 days |
| **TrollStore** | A TrollStore-compatible iOS version | No expiry, no limit |

Requirements: **iOS 17.0 or newer** (the deployment target in `project.yml`) and an iPhone or iPad
(`TARGETED_DEVICE_FAMILY: 1,2`). The build carries no code signature, so the untrusted-developer
prompt is expected on first launch — trust it in
Settings → General → VPN & Device Management.

**Sideloadly, step by step**

1. Download and unpack `EnglishLearning-unsigned-ipa.zip`; the file inside is
   `EnglishLearning-unsigned.ipa`.
2. Connect the device by USB and trust this computer when iOS asks.
3. Launch Sideloadly, drag the `.ipa` onto the window, enter your Apple ID, press Start.
4. On the device, if iOS shows an untrusted developer prompt, go to
   Settings → General → VPN & Device Management → trust the profile.
5. Launch English Learning.

A **free** Apple ID issues a profile that expires in **7 days**. When the app stops launching, run
Sideloadly again — that is the renewal, not a bug. A paid Apple ID gets a year.

**Don't want a sideloading tool at all?** Build and run on the simulator locally, which needs no
account and no IPA:

```sh
brew install xcodegen
make project
make test
open EnglishLearning.xcodeproj     # then ⌘R with an iOS Simulator destination
```

That is the complete zero-credential path: `make project`, `make test`, `open`, Run.

---

## 8. Troubleshooting

**`error: xcodegen not found`**
`brew install xcodegen`, or `mint install xcodegen`. Needs 2.38+.

**`make project` succeeds but Xcode shows no `EnglishLearning` scheme**
The scheme list is generated from the `schemes:` block in `project.yml`. Confirm it is there, re-run
`make project`, then in Xcode right-click the scheme → Manage Schemes → Shared.

**`Cannot find 'EnglishCore' in scope`**
`App/` was compiled before the package dependency existed. `make clean && make project`, then build
again. If it persists, the package name in `packages:` does not match the `name:` in
`Packages/EnglishCore/Package.swift`.

**The artifact is missing — there is no `EnglishLearning-unsigned-ipa`**
The workflow did not run on that commit. It triggers on manual dispatch, on a `v*` tag, and on
pushes to `main`; it does not run on every branch or pull request. Check the commit SHA on the run
page against the SHA you are building, push to `main`, tag a release, or dispatch the workflow by
hand. If you dispatched it yourself and it still failed, read the job log — the failure is in the
archive step, not in packaging.

**The sideloading tool rejects the IPA as unsigned, or the install fails immediately**
Expected for this artifact. `EnglishLearning-unsigned.ipa` has no code signature by design (§7), so
Sideloadly, AltStore and TrollStore must re-sign it with your own identity before it will install —
Sideloadly does this automatically when you supply an Apple ID. If the tool refuses even after
re-signing, check: the IPA still ends in `.ipa` (you are not passing the `.zip`), the device is on
iOS 17.0+, the USB connection is trusted, and a free account has not hit its 3-app limit.

**The app installed but will not launch: "untrusted developer"**
Trust the profile: Settings → General → VPN & Device Management → the profile for your Apple ID →
*Trust*. This prompt is expected for a re-signed build, not a failure.

**The app installed and ran, then stopped launching a few days later**
A free Apple ID's profile expired after 7 days. Re-run the sideload; a paid Apple ID gets a year.

**Xcode asks for a developer team when running on a physical device**
The project declares no team, by design — there is no credential in this repository. Choose a
simulator destination and Run, or install the artifact from §7 with a sideloading tool instead.

**`Unable to find a destination` / wrong scheme**
`xcodebuild -project EnglishLearning.xcodeproj -list` shows the real scheme names. `make sim` lists
booted simulators; the CI build uses `-destination 'generic/platform=iOS Simulator'`, which needs no
specific device.

**`SwiftData` models fail to build on Linux**
Expected. Only `Packages/EnglishCore` is portable. SwiftData lives in `Packages/EnglishStore` and is
tested on macOS in CI.

**App installs but crashes at launch with a missing-content error**
A content JSON file is malformed or a topic id in `content.json` has no `topics/<id>.json`. Run
`make validate-content`. The JSON schema is in `docs/ARCHITECTURE.md` §1.

**The app shows no topic cards but the build succeeded**
Content is loaded from the `EnglishCore` bundle resources. Confirm
`Packages/EnglishCore/Package.swift` declares the `content` directory in
`resources: [.copy("Resources/content")]` — `.copy` keeps the directory structure, `.process` may not
give the path `ContentLibrary` expects.
