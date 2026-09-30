# Build, Signing and Distribution Runbook

For a developer who has never seen this repository. Everything below assumes a Mac with Xcode 16
and a shell in the repository root.

- [1. Local setup](#1-local-setup)
- [2. Generating the Xcode project](#2-generating-the-xcode-project)
- [3. Running tests](#3-running-tests)
- [4. Validating content](#4-validating-content)
- [5. The generated project is generated](#5-the-generated-project-is-generated)
- [6. Continuous integration](#6-continuous-integration)
- [7. Unsigned IPA — the no-credentials path](#7-unsigned-ipa--the-no-credentials-path)
- [8. Signed IPA — the full Apple Developer path](#8-signed-ipa--the-full-apple-developer-path)
- [9. Secrets policy](#9-secrets-policy)
- [10. Rotating credentials](#10-rotating-credentials)
- [11. Troubleshooting](#11-troubleshooting)

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
| Signing style | Automatic, `DEVELOPMENT_TEAM` empty by default |
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
| `signed-ipa` | macos-latest | Full signing path. **Skipped** unless `APPLE_TEAM_ID` exists as a secret. |

`permissions: contents: read` everywhere. A `concurrency` group per ref cancels superseded runs, so
pushing twice does not queue two builds.

### `Unsigned IPA` (`.github/workflows/unsigned-ipa.yml`)

Manual dispatch (with a `configuration` input), every `v*` tag, and every push to `main`. Archives
with signing disabled, zips `Payload/EnglishLearning.app` into an unsigned IPA, uploads the IPA and
the `.xcarchive` as artifacts, and attaches the IPA to a GitHub Release when the trigger is a tag.
SPM resolution and DerivedData are cached on the `Package.resolved` + `project.yml` hash.

### `Signed IPA` (`.github/workflows/signed-ipa.yml`)

Manual dispatch only, never automatic. Requires all five secrets from §8. Optionally uploads to App
Store Connect via the `upload_to_appstore` input. Its concurrency group does **not** cancel
in-progress runs: cancelling midway can leave a half-issued signing asset.

---

## 7. Unsigned IPA — the no-credentials path

Use this when you have no Apple Developer membership, or you just want a build on your own device.

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

**Why iOS will not install it directly.** The binary inside an unsigned IPA has no embedded
provisioning profile and no valid signature. iOS refuses to launch it. A re-signing tool injects
your own identity and profile at install time:

| Tool | Needs | Free account limit |
| --- | --- | --- |
| **Sideloadly** | Windows/macOS, Apple ID + password, or a .p12 | 3 apps, re-sign every 7 days |
| **AltStore** | macOS (or on-device with AltStore) | 3 apps, refreshed every 7 days |
| **TrollStore** | A TrollStore-compatible iOS version | No expiry, no limit |

Install with Sideloadly: connect the device by USB, drag `EnglishLearning-unsigned.ipa` onto the
window, enter the Apple ID, Start. If iOS shows an untrusted developer prompt, go to
Settings → General → VPN & Device Management → trust the profile. Free Apple IDs produce a profile
that expires in 7 days; re-run the sideload to refresh it.

**Local equivalent:** `make archive-unsigned` produces the same archive without packaging the IPA.

---

## 8. Signed IPA — the full Apple Developer path

Prerequisites: a paid [Apple Developer Program](https://developer.apple.com/programs/) membership
($99/year), an App Store Connect app record, and a distribution signing identity.

### 8.1 Create the App ID

1. [developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)
   → **+** → **Apps** → **App**.
2. Description `English Learning`, Bundle ID **Explicit** → `com.b.english`. It must match
   `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` exactly.
3. Enable the capabilities the app uses. The current build needs none beyond the default, but if you
   add sign-in with Apple or push notifications, enable them here and regenerate the profile.

### 8.2 Create the App Store Connect record

1. [appstoreconnect.apple.com/apps](https://appstoreconnect.apple.com/apps) → **+** → **New App**.
2. Name `English Learning`, primary language English, bundle id `com.b.english`.
3. Fill in the rating questionnaire, age rating, pricing and privacy details. The privacy nutrition
   label must declare microphone and speech-recognition data — both are declared in the generated
   Info.plist with usage strings.
4. The app must be in a state where it can be uploaded; a first build is a TestFlight build, which
   does not require the store listing to be finished.

### 8.3 Choose the credential: API key vs app-specific password

**Recommended — App Store Connect API key (`.p8`).** A team-scoped key, no Apple ID password, no
2FA prompt, and revocable instantly in App Store Connect → Users and Access → Integrations. This is
what you use for `xcrun altool`/`notarytool`/Transporter automation. Create it under
Users and Access → Integrations → App Store Connect API → Team Keys, then download the `.p8`
**once** — Apple does not let you download it again.

**Alternative — app-specific password.** Generated at
[appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords. It
works with a normal Apple ID, needs 2FA enabled, and can be revoked the same way. It is what the
workflow's `APPLE_ID` / `APPLE_APP_SPECIFIC_PASSWORD` pair is for.

Either way, **never put either credential in this repository.** See §9.

### 8.4 Create the distribution certificate and export the `.p12`

1. Xcode → Settings → Accounts → **Manage Certificates**, then **+** → **Apple Distribution**.
   Xcode creates and downloads it automatically. If you prefer Keychain Access: Keychain Access →
   Certificate Assistant → Create a Certificate, type **Apple Distribution**.
2. In Keychain Access, find the certificate (a `Apple Distribution: Your Name (TEAMID)` entry with
   a private key beneath it). Select **both** → right-click → **Export…**
3. Set a password. This becomes the `CERTIFICATE_PASSWORD` secret.
4. Save as `.p12` (Personal Information Exchange), then base64-encode it:

   ```sh
   base64 -i ~/Desktop/AppleDistribution.p12 -o ~/Desktop/AppleDistribution.p12.b64
   ```

5. Copy the single line of output — that is the `CERTIFICATE_P12_BASE64` secret.

   ```sh
   pbcopy < ~/Desktop/AppleDistribution.p12.b64
   ```

6. Delete the `.p12` and the base64 file from disk when you are done. Keep them somewhere encrypted
   (1Password, Keychain) if you need them offline.

### 8.5 Create the provisioning profile

Ad Hoc and TestFlight both work with an **App Store** type distribution profile:

1. [developer.apple.com/account/resources/profiles/list](https://developer.apple.com/account/resources/profiles/list)
   → **+** → **App Store**.
2. App ID → `com.b.english`.
3. Select the certificate from §8.4.
4. Name it `EnglishLearning`.

The workflow references this profile by name via `PROVISIONING_PROFILE_SPECIFIER=EnglishLearning`.
If you name it differently, change that in `.github/workflows/signed-ipa.yml`.

**Simpler alternative for macOS builds:** skip the manual profile entirely. Set your team in
Xcode → Settings → Accounts, leave `CODE_SIGN_STYLE=Automatic`, and Xcode creates and refreshes the
profile itself. The CI workflow uses manual signing specifically so it can run without a personal
Apple ID login.

### 8.6 Add the secrets

Repository → Settings → **Secrets and variables** → Actions → **New repository secret**. Add all
five:

| Secret | Value | Example |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10-character team id | `AB12CD34E5` |
| `APPLE_ID` | Apple ID used for App Store Connect | `you@example.com` |
| `APPLE_APP_SPECIFIC_PASSWORD` | From §8.3 | `abcd-efgh-ijkl-mnop` |
| `CERTIFICATE_P12_BASE64` | Single-line base64 of the `.p12` | `MIIJ...` (one line, no newlines) |
| `CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` | `••••` |

GitHub masks secret values in logs, but the workflow still never echoes them: each credential is
passed as an env var, the certificate is imported into a throwaway keychain and the file is deleted
immediately, and the keychain is destroyed in an `if: always()` step. Do not "helpfully" add an
`echo` debug step — that is how signing keys end up in build logs.

### 8.7 Run it

Actions → **Signed IPA** → Run workflow:

- `configuration`: `Release`
- `upload_to_appstore`: tick to push the IPA straight to App Store Connect via `altool`

What it does, in order: generates the project from `project.yml`, creates a temporary keychain,
imports the `.p12` and unlocks the key partition list (without this, codesign cannot use the key
non-interactively), archives with `-allowProvisioningUpdates` and manual signing, writes
`ExportOptions.plist` (`method: app-store-connect`, `teamID`, `signingStyle: manual`,
`uploadSymbols: true`, `stripSwiftSymbols: true`), exports the IPA, uploads it as the
`EnglishLearning-signed-ipa` artifact, and deletes the keychain.

The IPA artifact is a standard App Store IPA: submit it in App Store Connect → the app → Version →
Build, or upload it with Transporter.

### 8.8 Local signed build

To produce the same IPA without CI, use your own team:

```sh
xcodegen generate
xcodebuild -project EnglishLearning.xcodeproj -scheme EnglishLearning \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/EnglishLearning.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=AB12CD34E5 archive
xcodebuild -exportArchive -archivePath build/EnglishLearning.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist
```

`project.yml` ships `DEVELOPMENT_TEAM: ""` and `CODE_SIGN_STYLE: Automatic`, so a fresh clone builds
for the simulator with no Apple account at all. Override the team on the command line as above, or
set it in Xcode's Signing & Capabilities tab for your own machine only — never commit that change.

---

## 9. Secrets policy

**No credential is ever committed.** That is why `.gitignore` excludes `*.p12`, `*.pfx`, `*.cer`,
`*.mobileprovision`, `*.provisionprofile`, `*.certSigningRequest`, `*.p8` and `*.key`, and why
`ExportOptions.plist` is ignored too.

- Credentials live in GitHub Actions secrets (encrypted at rest, never printed in logs) or in your
  local Keychain.
- Signing happens only on macOS runners, only in a temporary keychain that is deleted in the same
  run.
- The `signed-ipa` job in `CI` is gated on `if: ${{ secrets.APPLE_TEAM_ID != '' }}`. With no
  secrets it is skipped, which is what makes it safe to run `CI` on pull requests from forks.
- Anyone with write access to the repository can read Actions secrets but cannot see their values.
  Keep the collaborator list small and require 2FA.
- If a secret ever leaks — a paste into an issue, a committed file, a compromised runner — revoke it
  at the source first, then clean up the history. Revocation is the only thing that actually helps.

---

## 10. Rotating credentials

| Credential | How to rotate | Downtime |
| --- | --- | --- |
| App-specific password | Revoke and create a new one at appleid.apple.com → Sign-In and Security. Update `APPLE_APP_SPECIFIC_PASSWORD`. | None |
| App Store Connect API key | Users and Access → Integrations → revoke the key, create a new `.p8`. | None |
| Distribution certificate | Revoke the old one in Xcode (or the portal), create a new `Apple Distribution`, re-export the `.p12`, update both `CERTIFICATE_*` secrets. | You cannot build signed until both are updated. |
| Provisioning profile | Recreate in the portal with the same name `EnglishLearning`. If revoked, the next `xcodebuild -allowProvisioningUpdates` recreates it. | Rebuild required |
| `APPLE_TEAM_ID` | Effectively permanent. If the team is deleted, the bundle id moves to a new team. | Migration project |

The signing material expires on Apple's schedule, not yours: certificates after one year,
profiles after one year (or shorter for Ad Hoc with 100 devices), and **free** Apple ID profiles
after 7 days. The `Signed IPA` workflow is manual on purpose — run it when you intend to ship, not
on every commit.

---

## 11. Troubleshooting

**`error: xcodegen not found`**
`brew install xcodegen`, or `mint install xcodegen`. Needs 2.38+.

**`make project` succeeds but Xcode shows no `EnglishLearning` scheme**
The scheme list is generated from the `schemes:` block in `project.yml`. Confirm it is there, re-run
`make project`, then in Xcode right-click the scheme → Manage Schemes → Shared.

**`Cannot find 'EnglishCore' in scope`**
`App/` was compiled before the package dependency existed. `make clean && make project`, then build
again. If it persists, the package name in `packages:` does not match the `name:` in
`Packages/EnglishCore/Package.swift`.

**`Signing for "EnglishLearning" requires a development team`**
Building for a device or archiving without a team. Either pick a team in Xcode's Signing &
Capabilities tab, or build for the simulator with
`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`, which is what CI does.

**`No profiles for 'com.b.english' were found`**
The profile is missing, revoked, or belongs to another team. Confirm `PROVISIONING_PROFILE_SPECIFIER`
matches the profile name exactly, and keep `-allowProvisioningUpdates` on the archive step.

**`errSecInternalComponent` / codesign cannot find the private key**
The key partition list was not set. The workflow calls
`security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD"`.
If you build locally and see this, open Keychain Access, double-click the key → Access Control →
confirm "Allow all applications to access this item".

**`Unable to authenticate` / `The request cannot be completed because it requires a login`**
The app-specific password was revoked, or 2FA was enabled on the Apple ID after the password was
created — Apple invalidates app-specific passwords in that case. Make a new one.

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

**Version number rejected by App Store Connect**
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are in `project.yml`. Bump
`CURRENT_PROJECT_VERSION` for every upload; reusing a build number is rejected.
