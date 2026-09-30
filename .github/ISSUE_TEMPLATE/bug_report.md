---
name: Bug report
about: Something in the app behaves incorrectly
title: "[bug] "
labels: [bug]
body:
  - type: markdown
    attributes:
      value: |
        English Learning is fully offline. Please describe only what you can
        reproduce without a network connection.

  - type: input
    id: version
    attributes:
      label: App version
      description: The version shown on the Profile screen, or the tag you installed.
      placeholder: "1.0.0 (1)"
    validations:
      required: true

  - type: input
    id: device
    attributes:
      label: Device and iOS version
      placeholder: "iPhone 14, iOS 18.2"
    validations:
      required: true

  - type: dropdown
    id: install
    attributes:
      label: How did you install the app
      options:
        - Xcode (make project + run)
        - Signed IPA from CI
        - Unsigned IPA via Sideloadly / AltStore / TrollStore
        - Other
    validations:
      required: true

  - type: dropdown
    id: area
    attributes:
      label: Area
      options:
        - Content loading / missing topic
        - Exercise grading or feedback
        - Dictation
        - Vocabulary / spaced repetition
        - Listening or audio playback
        - Speaking
        - IELTS
        - Progress, streak, XP, achievements
        - Notifications
        - Home dashboard
        - Crash / app will not launch
        - Other
    validations:
      required: true

  - type: textarea
    id: what-happened
    attributes:
      label: What happened
      description: What you expected, and what happened instead.
    validations:
      required: true

  - type: textarea
    id: steps
    attributes:
      label: Steps to reproduce
      value: |
        1.
        2.
        3.
    validations:
      required: true

  - type: textarea
    id: content-id
    attributes:
      label: Content ids involved
      description: |
        Topic id, lesson id and exercise id if the bug is content related.
        These are the kebab-case ids from the JSON files, e.g. `tenses` /
        `tenses-present-simple` / `ex-tenses-ps-1`.
      placeholder: "tenses-present-simple"

  - type: textarea
    id: logs
    attributes:
      label: Console output or crash log
      description: From Xcode console, or Settings > Privacy > Analytics.
      render: text
