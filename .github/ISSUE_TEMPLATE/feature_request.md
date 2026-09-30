---
name: Feature request
about: Suggest a change to content, features or tooling
title: "[feature] "
labels: [enhancement]
body:
  - type: markdown
    attributes:
      value: |
        Read `docs/ARCHITECTURE.md` before filing. The module layout and the
        public API are a frozen contract, so a request that requires renaming a
        type or changing a signature needs a different conversation than a
        feature that fits the existing surface.

  - type: dropdown
    id: area
    attributes:
      label: Area
      options:
        - Content (new topic, lesson, exercise or vocabulary)
        - Curriculum / progression
        - Exercises or grading
        - Dictation
        - Vocabulary review
        - Audio or video
        - IELTS
        - Progress, streak, XP, achievements
        - Notifications
        - UI / navigation
        - Build, CI or tooling
        - Documentation
    validations:
      required: true

  - type: textarea
    id: problem
    attributes:
      label: Problem
      description: What are you trying to do that the app does not support today?
    validations:
      required: true

  - type: textarea
    id: proposal
    attributes:
      label: Proposed solution
      description: |
        If this needs new content, give the topic or lesson id and the kinds of
        exercises involved. See section 3 of docs/ARCHITECTURE.md for the
        content rules (no invented English, no dead URLs, minimum 8 exercises
        per grammar topic across at least 6 kinds).
    validations:
      required: true

  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives considered

  - type: checkboxes
    id: offline
    attributes:
      label: Constraints
      options:
        - label: This must work fully offline.
        - label: This must not add a third-party dependency.
        - label: This can be implemented entirely inside the existing public API of EnglishCore / EnglishStore.
