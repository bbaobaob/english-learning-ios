# Content audit

Triage of `Scripts/validate_content.py` against the frozen contract in
`ARCHITECTURE.md` §1–§3 and the Swift decoder, after the content model changed
underneath the validator.

- **Validator before:** 71 errors, 206 warnings (the brief said 72; the run said 71).
- **Validator after:** 0 errors, 25 warnings.
- Every surviving warning is a real content or copy defect, listed below.
- Nothing in `Packages/EnglishCore/Resources/content/` was changed by this pass.
  Every defect below is a report, not a fix.

Rule of thumb used throughout: **the decoder wins.** `IELTS.swift`, `Exercise.swift`,
`LessonStep.swift` and `ContentLibrary.swift` decide what can load;
`ARCHITECTURE.md` records the intent. Where they disagree, the disagreement is
printed by the validator as a `DOC DECISION` note rather than being resolved
silently in either direction.

---

## 1. Rules deleted

Each of these was reporting content that is correct.

| Deleted rule | Before | Why it was wrong |
|---|---|---|
| `ielts-kind` | 64 errors | `IELTSQuestion` is now `public typealias IELTSQuestion = Exercise` (`IELTS.swift:22`). The 13-case `IELTSQuestion.Kind` enum it tested against no longer exists, so all 113 shipped questions were "wrong". IELTS questions now go through `check_exercise`, the same path as the rest of the corpus. |
| `undocumented-kind` | 32 warnings | `listening` is an `ExerciseKind` case (`Exercise.swift:9`) and the shipped uses of it are well-formed (speech clip + answer). `ARCHITECTURE.md` §1's table has no row for it; the decoder is the authority, so `listening` is now a first-class row in `EXPECTED_ANSWER_TYPE`. Missing-table noise, not content risk. |
| `matching-reuse` | 20 warnings | §1 says "each `matchKey` group is used once". 20 exercises match many items to one group on purpose — six nouns to `{countable, uncountable}`, five word positions to `{before the main verb, end of the sentence}`. Grading is exact map equality, so these grade correctly. The doc line is the stale side. Replaced by a rule that distinguishes one-to-one from category matching (§3). |
| `matching-answer` (as written) | 4 errors | It required `answer.values == {item.id: item.matchKey}`. §1 now says the value is a *free-form label* — `"1"`, `"ii"`, `"A"` — and `matchKey` is only the item's group. All 4 errors were IELTS map-labelling and matching-information questions authored exactly as §1 describes. Replaced by `matching-keys` / `matching-one-to-one` (errors) and `matching-label` (warn). |
| `dictation-as-exercise` | 5 warnings | `kind: "dictation"` is a documented `ExerciseKind` with a documented answer type (§1 table row `dictation \| — \| text`). All 5 uses carry a speech clip and a text answer. "A DictationStep is the documented carrier" was never true — it is the *other* carrier. |
| `ielts-transcript` (required) | 3 errors | `IELTSLesson.transcript` defaults to `[]` (`IELTS.swift:45`). A reading lesson has no audio and correctly has no transcript; the 3 errors were `ielts-r-p1`, `ielts-r-p2`, `ielts-r-p3`. Now: a **listening** lesson with no transcript is a warning; any lesson is fine. |
| `answer-key` (boolean `value`, as an error) | 0 | `Answer.decodeBoolean` (`Exercise.swift:159`) accepts `value`, a bare string and a single-element array on purpose. Erroring on a form the decoder handles would re-block content the tolerance exists to rescue. Demoted to a warning (§4). |
| nested-array tolerance in the `rearrangeWords` check | 0 | The old branch flattened `values: [[...]]` and called it "several accepted orderings". `AnswerValue.order` holds exactly one `[String]`; a nested list **throws** in `Answer.init(from:)` and removes the whole topic from the library. The tolerance was what let 25 broken answers sit unnoticed. Deleted; `answer-decode` errors on the shape instead. |

## 2. Rules changed

| Rule | Before | After | Reason |
|---|---|---|---|
| `difficulty-drift` | 95 warnings | `difficulty-jump`, 14 warnings | Verdict below. |
| `step-order` | 23 warnings, one per file | 0 | Verdict below. |
| `ielts-range` | 26 warnings | 2 warnings | Verdict below. |

### `difficulty-drift` → `difficulty-jump` — verdict: ±1 is legitimate authoring

An exercise's `difficulty` is a *per-exercise* field. That is the only reason it
exists: `Exercise.difficulty` (`Exercise.swift:198`) is separate from the lesson's
`level`, and nothing in `ARCHITECTURE.md` requires the two to be equal — §3
constrains the lesson-level progression across a topic ("grammar topics progress
beginner → intermediate → advanced across their lessons"), not this field.
`progressing learner` content also needs one hard item inside an easy lesson.

Measured over all 1182 topic-corpus exercises:

| Δ (exercise − lesson) | count | verdict |
|---|---|---|
| −2 | 10 | reported — mis-tag |
| −1 | 100 | legitimate, silent |
| 0 | 841 | — |
| +1 | 218 | legitimate, silent |
| +2 | 13 | reported — mis-tag |

318 exercises differ from their lesson level; 95 of them by one level. Calling
those 95 defects was the rule inventing a constraint the contract does not have.
The rule now fires only at |Δ| ≥ 2, aggregated per lesson (14 lessons, 23
exercises — §5.3). The histogram is printed in the totals block so the judgement
stays visible instead of being asserted.

### `step-order` — verdict: the content is right, the doc is wrong

Offending files: **all 23 topic files that contain lessons** (`adjective`,
`adverb`, `alphabet`, `clauses`, `collocations`, `comparison`, `gerund-infinitive`,
`inversion`, `listening-skill`, `modal-verbs`, `noun`, `passive-voice`,
`reading-skill`, `reported-speech`, `speaking-skill`, `subject-verb-agreement`,
`subjunctive`, `tenses`, `types-of-condition`, `types-of-words`, `verb`,
`word-formation`, `writing-skill`), 160 of 160 lessons, always the same single
inversion: `exercises` before `dictation`.

That unanimity is the finding. There is no content bug; there is a doc bug.
`ARCHITECTURE.md` §3 states

> theory → video → examples → listening → dictation → practice → quiz → summary

which puts `dictation` before `practice` **and never names `exercises` at all** —
even though §1's step table defines both `practice` and `exercises`, and the
corpus ships `exercises` 160 times and `practice` 0 times. `LessonStep` and
`LearnSession` impose no ordering at all; the only order-sensitive rule in the app
is that `summary` must be last, and that is still checked (`summary-position`).

The five distinct real sequences, all consistent with each other:

```
111 × theory, examples, exercises, dictation, quiz, summary
 26 × theory, audio, examples, exercises, dictation, summary
 12 × theory, examples, exercises, dictation, summary
 10 × theory, audio, examples, exercises, summary
  1 × theory, examples, listening, exercises, dictation, quiz, summary
```

Resolution: the check follows the corpus convention (so 160 conforming lessons
are not reported as 160 defects) and the divergence is printed once as a
`DOC DECISION` note, naming the doc line that needs updating. The check is still
live — a lesson that puts a quiz before its practice content, or a summary in the
middle, is still caught.

**Action for the architecture owner (not done here — `ARCHITECTURE.md` is frozen):**
§3's sequence should read
`theory → video → audio → examples → listening → exercises → dictation → practice → quiz → summary`.

### `ielts-range` — verdict: 24 of the 26 were a bad rule, 2 are real copy defects

The old rule compared a *range span* to the *item count*. IELTS instructions quote
the paper's own numbering, and a lesson holds only part of it: `ielts-l-sec1` has
7 questions and its instructions legitimately read "Questions 1–4: match each place
on the map…" and "Questions 5–7: complete the notes below". The numbers refer to
the paper, not to the array index. That rule could only ever produce noise.

What *cannot* be right is an instruction numbering a question the lesson does not
contain. That is the rule now, and it finds exactly two real defects (§5.2).

---

## 3. Rules added

Every rule below has a fixture in `python3 Scripts/validate_content.py --selftest`
(12 cases, all passing). The self-test exists because the corpus is currently
clean: a validator that reports nothing is otherwise indistinguishable from one
that checks nothing.

| Rule | Severity | Catches |
|---|---|---|
| `answer-decode` (nested-list message) | error | `values` nested one level deeper than `[String]` — the 25 broken `rearrangeWords` answers. Names the shape in the message. |
| `answer-decode` (existing, boolean/string) | error | a string, object or number where `Bool`/`[String]`/`[String:String]` is decoded. Throws and removes the whole topic file. |
| `answer-unsatisfiable` | error | a `choice` answer naming an id that is not in the exercise's own `items` — the answer no learner response can produce. |
| `matching-keys` | error | a `pairs` answer whose key set is not exactly the item-id set. Grading compares maps key-for-key, so a missing or extra key is an unsatisfiable answer. |
| `matching-one-to-one` | error | an answer value reused where a bijection was actually available — i.e. every item has its own `matchKey`, so two items landing on one value leaves another unreachable. Reuse across few groups (the category-matching case) is not flagged. |
| `matching-label` | warn | answer values that are labels (`"1"`, `"ii"`, `"A"`) rather than the items' `matchKey`s. Legal per §1, recorded because the answer can no longer be read off the items. |
| `boolean-shape` | warn | a `boolean` answer that is not a real JSON bool under `values` (`value`, `"true"`, `["true"]`). These decode; the warning exists because the strict form once graded every True/False question as false with nothing on screen to say so. All 97 boolean answers in the corpus are canonical. |
| `audio-required` (missing-clip case) | error | an audio-bearing kind (`listening`, `listeningComprehension`, `dictation`) with **no** audio clip. The old rule only fired on a *remote* clip, so a completely silent question passed. 47/47 now verified. |
| `exercise-kind` (now covering IELTS) | error | an IELTS question whose `kind` is not an `ExerciseKind` case — the direct replacement for `ielts-kind`. |
| `answer-kind-mismatch` (now covering IELTS) | error | an IELTS `answer.type` inconsistent with its `ExerciseKind` row. |
| `ielts-skill` | error | a lesson `skill` that is not an `IELTSSkill` case, or a lesson with no skill in a module that has none either — `IELTSModule.skills` (`IELTS.swift:105`) cannot resolve it. Module `skill` is optional and is only a headline label; nothing is inferred from it, because `ielts-listening-reading.json` ships two papers in one module. |
| `ielts-audio` | error | a listening lesson with no audio clip — silent lesson, zero bundled assets. |
| `ielts-transcript` | warn | a **listening** lesson with no transcript lines. |
| `module-id`, `module-id-dupe` | error | non-kebab or duplicated module id. |
| `difficulty-jump` | warn | an exercise two or more levels from its lesson (§2). |

Checks that already existed and are now **verified to fire** by the self-test:
`topic-level` (a `Topic` with no top-level `level` — the defect that hit 4 topics)
and `step-payload` for a `dictation` step with no items.

---

## 4. Content defects still outstanding

None of these are stale rules. All 25 remaining warnings are real.

### 4.1 Five shipped topics are missing from `content.json` (5 warnings, highest impact)

`content.json` lists 19 topic ids. 24 topic files exist. `ContentLibrary.orderTopics`
(`ContentLibrary.swift:198`) appends unlisted topics *in file order* after the
listed ones, so these five load and are reachable, but they sit at the end of the
course instead of in the position their filename implies — and `make validate-content`
only walks the 19 listed ids, so it cannot see them at all.

| File | Should be |
|---|---|
| `topics/listening-skill.json` | added to `content.json` `topicIDs`, after `methods` |
| `topics/methods.json` | added to `content.json` `topicIDs`, at the position §3's topic list implies |
| `topics/reading-skill.json` | added to `content.json` `topicIDs` |
| `topics/speaking-skill.json` | added to `content.json` `topicIDs` |
| `topics/writing-skill.json` | added to `content.json` `topicIDs` |

Fixing this also requires updating the `EXPECTED = 19` count in `make validate-content`
and `EXPECTED_TOPIC_COUNT = 19` in `.github/workflows/ci.yml`; both are outside this
lane's write scope.

### 4.2 Two IELTS lessons number questions that do not exist (2 warnings)

| File | Question | Problem | Should be |
|---|---|---|---|
| `ielts-listening-reading.json` | `ielts-r-p2-q6` | instruction reads "Questions 6–9: match each paragraph, A to D, with the correct heading". The lesson ships 6 questions and this one question *is* all four paragraphs | "Question 6", or renumber the lesson's six questions 1–6 |
| `ielts-listening-reading.json` | `ielts-r-p3-q2`, `q3`, `q4` | instructions read "Questions 6–8", but the lesson ships 6 questions and these three are its 2nd–4th | "Questions 2–4" |

Cosmetic and learner-visible (the instruction text is rendered above each
question), but the numbering is simply wrong. The other 24 `ielts-range` hits the
old rule produced were correct content — `ielts-l-sec2-q1`'s "Questions 1–4: match
each place on the map" with questions 5–7 elsewhere in the same lesson is the
paper's numbering, not an array index.

### 4.3 Twenty-three exercises tagged two levels from their lesson (14 warnings)

See the table in §2 — 23 exercises across 14 lessons, e.g.
`adjective-l4-ex3` (`beginner` in an `advanced` lesson) and `adverb-l2-ex5`
(`advanced` in a `beginner` lesson). Either the tag or the lesson level is wrong;
the questions themselves read as ordinary level-appropriate items, so most likely
the `difficulty` tag was copied from a neighbouring lesson. Full list in §5.3.

### 4.4 Four matching answers use labels rather than `matchKey`s (4 warnings)

| File | Question | Answer values | Items' `matchKey`s |
|---|---|---|---|
| `ielts-listening-reading.json` | `ielts-l-sec2-q1` | `"1" "2" "3" "4"` | `"A" "B" "C" "D"` |
| `ielts-listening-reading.json` | `ielts-l-sec3-q1` | `"1" "2" "3" "4"` | `"A" "B" "C" "D"` |
| `ielts-listening-reading.json` | `ielts-r-p2-q6` | `"i" "ii" "iii" "iv"` | `"A" "B" "C" "D"` |
| `ielts-listening-reading.json` | `ielts-r-p3-q1` | `"A" "B" "C" "D" "E"` | `"1" "2" "3" "4" "5"` |

**Not a defect** — §1 sanctions it and `ExerciseEngine.matchingKeys(for:)`
(`ExerciseEngine.swift:261`) registers both an item's `id` and its `matchKey`, so
the UI resolves either orientation. Left as a warning because the authored answer
no longer mirrors `items[].matchKey`, which is a trap for the next editor.

### 4.5 Observation, no rule: the four listening lessons have no `prompt`

`ielts-l-sec1` … `ielts-l-sec4` each carry 20–27 transcript lines and a speech
clip, but no `prompt` — the field §1 describes as "the task text or passage
heading shown above the lesson". A learner gets the audio and the questions with
nothing stating the task ("You will hear a conversation about a campus tour…").
It decodes fine (`prompt` is `String?`), so this is a content gap rather than a
defect, and no rule is raised for it: `writing` and `speaking` lessons all have
prompts, so the four listening ones look like an oversight rather than a policy.
Worth a decision by whoever owns the IELTS content.

---

## 5. Doc and comment debt found while triaging

Not content. Each of these is a stale statement that made a validator rule look
correct when it was not.

### 5.1 `ExerciseEngine.swift:212-223`

> `Answer.pairs` has two legal shapes … 2. **Domain-keyed** — `items` is absent or empty
> … Note that shipped content also keys some item-based answers by `matchKey` rather than by
> `item.id` (`ielts-l-sec2-q1`, `ielts-r-p3-q1`), so nothing here may assume id keys.

Both claims are false against the current data: all 71 shipped `matching` exercises
have non-empty `items`, and both named questions key their answers by `item.id`
(`ielts-l-sec2-q1` → `{mapA: "1", …}`, `ielts-r-p3-q1` → `{mi1: "A", …}`). The new
`matching-keys` rule relies on the key set being the item-id set, which is now true
of 71/71. The comment should be corrected so nobody reintroduces the
key-by-`matchKey` shape.

### 5.2 `ARCHITECTURE.md` §1, `IELTSModule` block

The schema comment still lists a 13-case IELTS kind set
(`formCompletion`, `noteCompletion`, `mapLabeling`, `trueFalseNotGiven`,
`yesNoNotGiven`, `matchingHeadings`, `matchingInformation`, `summaryCompletion`,
`diagramLabeling`) that no longer exists in the decoder and that no shipped
question uses. It also still shows `skill` and `transcript` as if they were
required per module/per lesson. Should be updated to `IELTSQuestion = Exercise`
with a per-lesson `skill`.

### 5.3 Difficulty mis-tags, full list

| File | Lesson | Lesson level | Exercise | Tagged |
|---|---|---|---|---|
| `adjective.json` | `adjective-degree-modifiers` | advanced | `adjective-l4-ex3` | beginner |
| `adjective.json` | `adjective-prepositional-patterns` | advanced | `adjective-l5-ex1` | beginner |
| `adjective.json` | `adjective-prepositional-patterns` | advanced | `adjective-l5-q2` | beginner |
| `adverb.json` | `adverb-formation` | beginner | `adverb-l2-ex5` | advanced |
| `clauses.json` | `clauses-relative` | beginner | `cl-rl-q3` | advanced |
| `clauses.json` | `clauses-relative` | beginner | `cl-rl-q4` | advanced |
| `collocations.json` | `collocations-verb-noun` | beginner | `col-vn-q3` | advanced |
| `collocations.json` | `collocations-adjective-noun` | beginner | `col-an-q3` | advanced |
| `collocations.json` | `collocations-adjective-noun` | beginner | `col-an-q4` | advanced |
| `comparison.json` | `comparison-double-forms` | advanced | `comparison-l6-ex1` | beginner |
| `comparison.json` | `comparison-double-forms` | advanced | `comparison-l6-ex2` | beginner |
| `comparison.json` | `comparison-double-forms` | advanced | `comparison-l6-q1` | beginner |
| `inversion.json` | `iv-l1` | beginner | `iv-l1-e5` | advanced |
| `inversion.json` | `iv-l1` | beginner | `iv-l1-q4` | advanced |
| `types-of-condition.json` | `cond-first` | beginner | `cd-1-q2` | advanced |
| `types-of-condition.json` | `cond-first` | beginner | `cd-1-q4` | advanced |
| `verb.json` | `verb-five-forms` | beginner | `verb-l2-q4` | advanced |
| `verb.json` | `verb-phrasal-verbs` | advanced | `verb-l4-ex3` | beginner |
| `verb.json` | `verb-tense-and-agreement` | advanced | `verb-l5-ex1` | beginner |
| `verb.json` | `verb-tense-and-agreement` | advanced | `verb-l5-ex3` | beginner |
| `verb.json` | `verb-tense-and-agreement` | advanced | `verb-l5-q2` | beginner |
| `word-formation.json` | `word-formation-prefixes` | beginner | `wf-pref-q4` | advanced |
| `word-formation.json` | `word-formation-noun-suffixes` | beginner | `wf-noun-q4` | advanced |

---

## 6. Wiring: the validator is not in CI

The brief states the validator is wired into `make validate-content` and the
`lint-content` job. It is not, and neither call site was changed here (both are
outside this lane's write scope):

- `Makefile:42` `validate-content` pipes an inline `python3 -` script that checks
  only that every JSON parses, that `content.json` lists 19 ids, and that each
  listed id has a file. It never invokes `Scripts/validate_content.py`. It exits 0
  today: `content ok: 28 json files, 19 topics`.
- `.github/workflows/ci.yml:62` `lint-content` runs a near-identical inline script.
  Same result, same blind spots.

So a green `make validate-content` proves the JSON parses; it does not prove the
content validates. To make this report trustworthy in CI, `make validate-content`
should end with `python3 Scripts/validate_content.py`, and the CI job should run
the same target. The two `EXPECTED_TOPIC_COUNT = 19` constants also need to
become 24 whenever §4.1 is fixed — until then, the five unlisted topics are
invisible to both scripts.
