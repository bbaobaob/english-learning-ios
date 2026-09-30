#!/usr/bin/env python3
"""Content validator for Packages/EnglishCore/Resources/content/.

Stdlib only. Walks the content tree, checks it against the frozen schema in
docs/ARCHITECTURE.md section 1 and the content rules in section 3, and prints
errors first, then warnings, then corpus totals.

    python3 Scripts/validate_content.py          # exit 1 on errors, 0 on warnings only
    python3 Scripts/validate_content.py --quiet  # totals only

Where docs/ARCHITECTURE.md and the Swift decoder
(Packages/EnglishCore/Sources/EnglishCore/Content/*.swift) disagree, the decoder
wins; the disagreement is reported as DOC_DECISION, not silently resolved.
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = "Packages/EnglishCore/Resources/content"
TOPICS_DIR = os.path.join(ROOT, "topics")
INDEX = os.path.join(ROOT, "content.json")

# --- Frozen enums, transcribed from the Swift decoder (the truth). ----------

LEVELS = ("beginner", "intermediate", "advanced")
TOPIC_KINDS = (
    "grammar", "alphabet", "methods", "listening",
    "speaking", "reading", "writing", "ielts", "vocabulary",
)
STEP_TYPES = (
    "theory", "video", "audio", "examples", "practice",
    "exercises", "dictation", "listening", "quiz", "summary",
)
EXERCISE_KINDS = (
    "multipleChoice", "multiSelect", "fillInTheBlank", "dictation", "listening",
    "typeTheAnswer", "trueFalse", "matching", "rearrangeWords",
    "sentenceCompletion", "errorCorrection", "wordFormation", "translation",
    "reading", "listeningComprehension", "grammarCorrection",
)
ANSWER_TYPES = ("text", "choice", "pairs", "order", "boolean", "none")
IELTS_KINDS = {
    "multipleChoice", "matching", "formCompletion", "noteCompletion",
    "sentenceCompletion", "mapLabeling", "diagramLabeling", "dictation",
    "trueFalseNotGiven", "yesNoNotGiven", "matchingHeadings",
    "matchingInformation", "summaryCompletion",
}
IELTS_SKILLS = ("listening", "reading", "writing", "speaking")

# docs/ARCHITECTURE.md section 1, "answer.type and items shape per exercise kind".
# trueFalse accepts either boolean or choice -- that is intentional.
EXPECTED_ANSWER_TYPE = {
    "multipleChoice": "choice",
    "multiSelect": "choice",
    "trueFalse": ("boolean", "choice"),
    "fillInTheBlank": "text",
    "typeTheAnswer": "text",
    "dictation": "text",
    "matching": "pairs",
    "rearrangeWords": "order",
    "sentenceCompletion": "text",
    "errorCorrection": "text",
    "wordFormation": "text",
    "translation": "text",
    "reading": "choice",
    "listeningComprehension": "choice",
    "grammarCorrection": "text",
}
# Not in the section 1 table at all. `listening` is an ExerciseKind case in the
# decoder and is used by shipped content with both text and choice answers.
UNDOCUMENTED_KINDS = {"listening": ("text", "choice")}

# Kinds that must carry their own audio stimulus (keeps the app asset-free).
AUDIO_REQUIRED_KINDS = ("listening", "listeningComprehension", "dictation")

# section 3: theory -> video -> examples -> listening -> dictation -> practice -> quiz -> summary
STEP_ORDER = (
    "theory", "video", "audio", "examples", "listening",
    "dictation", "practice", "exercises", "quiz", "summary",
)
PRACTICE_CONTENT = ("exercises", "dictation", "listening", "practice")

KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
IPA = re.compile(r"^/.+/$", re.S)
BAND = re.compile(r"^\d+(\.\d+)?$")
QUESTION_RANGE = re.compile(r"[Qq]uestions?\s*(\d+)\s*[-–—]\s*(\d+)")

# Placeholders that must never appear in a committed URL.
URL_PLACEHOLDER = re.compile(
    r"^(|\s)*(todo|tbd|none|null|n/?a|example\.com|placeholder|xxx+)\s*$", re.I
)


class Report:
    """Errors, warnings and doc/decoder disagreements, in emission order."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []
        self._counts: Counter = Counter()

    def error(self, kind: str, where: str, message: str) -> None:
        self.errors.append(f"{where} — [{kind}] {message}")
        self._counts[kind] += 1

    def warn(self, kind: str, where: str, message: str) -> None:
        self.warnings.append(f"{where} — [{kind}] {message}")
        self._counts[kind] += 1

    def count(self, kind: str) -> int:
        return self._counts[kind]

    def by_kind(self, bucket: list[str]) -> Counter:
        out: Counter = Counter()
        for line in bucket:
            m = re.search(r"—\s*\[([^\]]+)\]", line)
            out[m.group(1) if m else "?"] += 1
        return out


class LineIndex:
    """Finds the 1-based line of a JSON object by its `id` value.

    Cheap and good enough: content ids are unique per file, so the first match is
    the right one. Falls back to the line of the enclosing key when unknown.
    """

    def __init__(self, raw: str, rel: str) -> None:
        self._lines = raw.splitlines()
        self._rel = rel
        self._cache: dict[str, int] = {}

    def line_of_id(self, ident: str | None) -> int:
        if not ident:
            return 1
        if ident in self._cache:
            return self._cache[ident]
        needle = '"%s"' % ident
        for n, line in enumerate(self._lines, 1):
            if needle in line:
                self._cache[ident] = n
                return n
        return 1

    def line_of(self, needle: str) -> int:
        for n, line in enumerate(self._lines, 1):
            if needle in line:
                return n
        return 1

    def at(self, ident: str | None) -> str:
        return "%s:%d" % (self._rel, self.line_of_id(ident))


def is_nonempty_str(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def unknown_keys(obj: dict, allowed: set) -> list[str]:
    return sorted(k for k in obj if k not in allowed)


def multiset(values) -> Counter:
    return Counter(values)


# --- Per-file loaders -------------------------------------------------------


class LoadedFile:
    def __init__(self, rel: str, path: str, data, index: LineIndex) -> None:
        self.rel = rel
        self.path = path
        self.data = data
        self.index = index


def load_json(path: str, rel: str, report: Report):
    """Parse one JSON file. Returns None (and reports) when it will not parse."""
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as exc:
        report.error("unreadable", rel, str(exc))
        return None
    if not raw.strip():
        report.error("empty-file", rel, "file is empty")
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        report.error(
            "invalid-json",
            "%s:%d:%d" % (rel, exc.lineno, exc.colno),
            "invalid JSON: %s" % exc.msg,
        )
        return None
    return LoadedFile(rel, path, data, LineIndex(raw, rel))


# --- Structural checks ------------------------------------------------------

STEP_PAYLOAD = {
    # type -> (required keys, optional keys)
    "theory": ({"heading", "body"}, {"rules"}),
    "video": ({"video"}, set()),
    "audio": ({"audio"}, {"title"}),
    "examples": ({"examples"}, set()),
    "practice": ({"exerciseIDs"}, {"title"}),
    "exercises": ({"exercises"}, set()),
    "dictation": ({"items"}, {"title"}),
    "listening": ({"exercises"}, {"title", "audio"}),
    "quiz": ({"questions"}, {"title", "passPercent"}),
    "summary": ({"takeaways"}, {"nextLessonID"}),
}
EXERCISE_KEYS = {
    "id", "kind", "topicID", "lessonID", "difficulty", "prompt", "instruction",
    "audio", "video", "items", "answer", "explanation", "xp", "translation",
}
ITEM_KEYS = {"id", "text", "isCorrect", "matchKey"}
AUDIO_KEYS = {"id", "kind", "text", "fileName", "url", "rate", "voiceID", "title"}
VIDEO_KEYS = {"id", "title", "source", "transcript", "subtitles", "durationSeconds"}


def check_audio_clip(clip, where: str, index: LineIndex, report: Report) -> None:
    if clip is None:
        return
    if not isinstance(clip, dict):
        report.error("audio-shape", where, "audio is not an object")
        return
    extra = unknown_keys(clip, AUDIO_KEYS)
    if extra:
        report.warn("unknown-key", where, "audio clip has unknown key(s) %s" % ", ".join(extra))
    kind = clip.get("kind")
    if kind is not None and kind not in ("speech", "file", "remote"):
        report.error("audio-kind", where, "audio.kind %r is not speech|file|remote" % kind)
    if kind == "speech" and not is_nonempty_str(clip.get("text")):
        report.error("speech-no-text", where, "audio.kind == \"speech\" but text is empty; nothing to speak")
    if kind == "file" and not is_nonempty_str(clip.get("fileName")):
        report.error("audio-file", where, "audio.kind == \"file\" but fileName is empty")
    if kind == "remote" and not is_nonempty_str(clip.get("url")):
        report.error("audio-remote", where, "audio.kind == \"remote\" but url is empty")


def check_video_clip(clip, where: str, report: Report, counts: Counter) -> None:
    if clip is None:
        return
    if not isinstance(clip, dict):
        report.error("video-shape", where, "video is not an object")
        return
    extra = unknown_keys(clip, VIDEO_KEYS)
    if extra:
        report.warn("unknown-key", where, "VideoClip has unknown key(s) %s" % ", ".join(extra))
    if not is_nonempty_str(clip.get("id")):
        report.error("video-id", where, "VideoClip.id missing or empty")
    source = clip.get("source")
    if not isinstance(source, dict):
        report.error("video-source", where, "VideoClip.source missing or not an object")
        return
    stype = source.get("type")
    counts[stype] += 1
    if stype not in ("remote", "bundled", "none"):
        report.error("video-source", where, "VideoClip.source.type %r is not remote|bundled|none" % stype)
    if stype == "remote":
        url = source.get("url")
        if not is_nonempty_str(url):
            report.error(
                "placeholder-url", where,
                "COMMITTED remote VideoClip with empty url — ARCHITECTURE.md s1 forbids dead URLs",
            )
        elif URL_PLACEHOLDER.match(url.strip()):
            report.error(
                "placeholder-url", where,
                "COMMITTED remote VideoClip with placeholder url %r — ship source.type == \"none\" instead"
                % url,
            )
    if stype == "bundled" and not is_nonempty_str(source.get("name")):
        report.error("video-bundled", where, "source.type == \"bundled\" but name is empty")
    for n, cue in enumerate(clip.get("subtitles") or [], 1):
        if not isinstance(cue, dict) or not {"start", "end", "text"} <= set(cue):
            report.error("subtitle-shape", where, "subtitles[%d] needs start, end and text" % (n - 1))


class Corpus:
    """Corpus-wide indexes and totals."""

    def __init__(self) -> None:
        self.exercise_ids: dict[str, list[str]] = defaultdict(list)
        self.lesson_ids: dict[str, list[str]] = defaultdict(list)
        self.kinds: Counter = Counter()
        self.dictation_items = 0
        self.quiz_questions = 0
        self.step_types: Counter = Counter()
        self.video_sources: Counter = Counter()
        self.audio_required_with_speech = 0
        self.audio_required_total = 0
        # lesson id -> Counter(difficulty -> count) for exercises whose difficulty
        # differs from the lesson level; reported once per lesson.
        self.drift: dict[str, Counter] = defaultdict(Counter)
        # rel path -> Counter("<stepA> before <stepB>") for s3 order violations.
        self.step_order: dict[str, Counter] = defaultdict(Counter)
        self.topics = 0
        self.lessons = 0
        self.exercises = 0
        self.ielts_questions = 0


def check_exercise(
    ex, topic_id: str, lesson_id: str, lesson_level, index: LineIndex,
    rel: str, report: Report, corpus: Corpus, origin: str,
) -> None:
    if not isinstance(ex, dict):
        report.error("exercise-shape", index.at(None), "exercise is not an object")
        return
    ex_id = ex.get("id")
    where = index.at(ex_id if isinstance(ex_id, str) else None)
    corpus.exercises += 1
    corpus.exercise_ids[ex_id].append("%s (%s)" % (rel, origin))
    corpus.kinds[ex.get("kind")] += 1

    if not is_nonempty_str(ex_id):
        report.error("exercise-id", where, "exercise has no id")
    elif not KEBAB.match(ex_id):
        report.error("exercise-id", where, "exercise id %r is not stable kebab-case" % ex_id)

    kind = ex.get("kind")
    if kind not in EXERCISE_KINDS:
        report.error("exercise-kind", where, "kind %r is not an ExerciseKind case" % kind)

    extra = unknown_keys(ex, EXERCISE_KEYS)
    if extra:
        report.warn("unknown-key", where, "exercise has unknown key(s) %s" % ", ".join(extra))

    if not is_nonempty_str(ex.get("topicID")):
        report.error("exercise-topic", where, "topicID missing (required — powers weak-area stats)")
    elif ex["topicID"] != topic_id:
        report.error("exercise-topic", where, "topicID %r != containing topic %r" % (ex["topicID"], topic_id))
    if ex.get("lessonID") != lesson_id:
        report.error(
            "exercise-lesson", where,
            "lessonID %r != containing lesson %r" % (ex.get("lessonID"), lesson_id),
        )

    difficulty = ex.get("difficulty")
    if difficulty not in LEVELS:
        report.error("difficulty", where, "difficulty %r is not beginner|intermediate|advanced" % difficulty)
    elif lesson_level is not None and difficulty != lesson_level:
        # Aggregated per lesson, not per exercise: 300-odd lines of this drowns
        # the report without telling anyone anything new.
        corpus.drift[lesson_id][difficulty] += 1

    prompt = ex.get("prompt")
    if not is_nonempty_str(prompt):
        report.error("prompt", where, "prompt missing or empty")

    explanation = ex.get("explanation")
    if not is_nonempty_str(explanation):
        report.error("explanation", where, "explanation missing or empty")
    elif len(explanation.strip()) < 20:
        report.error("explanation-short", where, "explanation is %d chars; at least 20 required" % len(explanation.strip()))

    xp = ex.get("xp")
    if xp is not None and (not isinstance(xp, int) or xp <= 0):
        report.error("xp", where, "xp %r must be a positive integer" % xp)

    items = ex.get("items")
    if items is not None and not isinstance(items, list):
        report.error("items-shape", where, "items is not an array")
        items = []
    for n, item in enumerate(items or [], 1):
        if not isinstance(item, dict):
            report.error("item-shape", where, "items[%d] is not an object" % (n - 1))
            continue
        bad = unknown_keys(item, ITEM_KEYS)
        if bad:
            report.warn("unknown-key", where, "items[%d] has unknown key(s) %s" % (n - 1, ", ".join(bad)))
        if not is_nonempty_str(item.get("id")):
            report.error("item-id", where, "items[%d] has no id" % (n - 1))

    check_audio_clip(ex.get("audio"), where, index, report)
    check_video_clip(ex.get("video"), where, report, corpus.video_sources)

    # Audio is what keeps the app asset-free: every audio-bearing kind must ship
    # a speech clip with text, not a bundled or remote asset.
    if kind in AUDIO_REQUIRED_KINDS:
        corpus.audio_required_total += 1
        clip = ex.get("audio")
        if isinstance(clip, dict) and clip.get("kind") == "speech" and is_nonempty_str(clip.get("text")):
            corpus.audio_required_with_speech += 1
        elif isinstance(clip, dict) and clip.get("kind") == "remote":
            report.error(
                "audio-required", where,
                "kind %s must carry a speech clip; this one points at a remote asset" % kind,
            )

    answer = ex.get("answer")
    if not isinstance(answer, dict):
        report.error("answer-shape", where, "answer missing or not an object")
        return
    atype = answer.get("type")
    values = answer.get("values")
    if atype not in ANSWER_TYPES:
        report.error("answer-type", where, "answer.type %r is not one of %s" % (atype, ", ".join(ANSWER_TYPES)))
        return

    expected = EXPECTED_ANSWER_TYPE.get(kind)
    if expected is None and kind in UNDOCUMENTED_KINDS:
        expected = UNDOCUMENTED_KINDS[kind]
        report.warn(
            "undocumented-kind", where,
            "kind %r is an ExerciseKind case but has no row in ARCHITECTURE.md s1; "
            "accepting answer.type %s" % (kind, "/".join(expected)),
        )
    if expected is not None:
        allowed = (expected,) if isinstance(expected, str) else expected
        if atype not in allowed:
            report.error(
                "answer-kind-mismatch", where,
                "kind %r requires answer.type %s, found %r"
                % (kind, " or ".join(allowed), atype),
            )

    # Decoder truth: the payload shape must be decodable as the type claims.
    # DOC_DECISION -- ARCHITECTURE.md never says what happens to a mismatched
    # payload; Answer.init(from:) uses decodeIfPresent, so a wrong type throws
    # and takes the whole file with it, or silently defaults.
    if atype == "boolean" and "value" in answer and "values" not in answer:
        report.error(
            "answer-key", where,
            "answer uses key \"value\"; the decoder reads \"values\" and will silently "
            "grade every response as false (intended %r)" % (answer.get("value"),),
        )
    if atype in ("text", "choice", "order"):
        if values is None:
            report.error("answer-values", where, "answer.values missing for type %r" % atype)
        elif not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            report.error(
                "answer-decode", where,
                "answer.type %r but values is %s; Answer.init(from:) decodes [String] and "
                "this THROWS, dropping the whole topic file"
                % (atype, type(values).__name__),
            )
    elif atype == "pairs" and values is not None and not isinstance(values, dict):
        report.error("answer-decode", where, "answer.type \"pairs\" but values is not an object")
    elif atype == "boolean" and values is not None and not isinstance(values, bool):
        report.error(
            "answer-decode", where,
            "answer.type \"boolean\" but values is %s; Answer.init(from:) decodes Bool and "
            "this THROWS, dropping the whole topic file" % type(values).__name__,
        )

    if kind == "multipleChoice":
        correct = [i["id"] for i in (items or [])
                   if isinstance(i, dict) and i.get("isCorrect") is True]
        if len(correct) != 1:
            report.error(
                "mc-correct-count", where,
                "multipleChoice must have exactly one isCorrect item, found %d %s"
                % (len(correct), sorted(correct)),
            )
        elif isinstance(values, list) and sorted(values) != sorted(correct):
            report.error(
                "mc-answer-set", where,
                "answer.values %s != the set of isCorrect item ids %s" % (sorted(values), sorted(correct)),
            )
        n_opts = len(items or [])
        if n_opts not in (3, 4):
            report.warn("mc-options", where, "multipleChoice has %d options (3 or 4 expected)" % n_opts)
    elif kind == "multiSelect":
        correct = sorted(i["id"] for i in (items or [])
                         if isinstance(i, dict) and i.get("isCorrect") is True)
        if len(correct) < 2:
            report.error(
                "ms-correct-count", where,
                "multiSelect needs at least two isCorrect items, found %d" % len(correct),
            )
        elif isinstance(values, list) and sorted(values) != correct:
            report.error(
                "ms-answer-set", where,
                "answer.values %s != the set of isCorrect item ids %s" % (sorted(values), correct),
            )
    elif kind == "rearrangeWords":
        tokens = [i.get("text") for i in (items or []) if isinstance(i, dict)]
        candidates = values if isinstance(values, list) else []
        flat = [v for c in candidates for v in c] if candidates and isinstance(candidates[0], list) else candidates
        if candidates and isinstance(candidates[0], list):
            # Multiple accepted orderings: each candidate must be a permutation.
            bad = [c for c in candidates if multiset(c) != multiset(tokens)]
            if bad:
                report.error(
                    "rearrange-tokens", where,
                    "%d accepted orderings are not a permutation of items[].text %s"
                    % (len(bad), bad[:1]),
                )
            if len(candidates) > 1:
                report.warn(
                    "rearrange-multi", where,
                    "%d accepted orderings; AnswerValue.order holds ONE order, so only the "
                    "first can ever be graded correct" % len(candidates),
                )
        elif multiset(flat) != multiset(tokens):
            report.error(
                "rearrange-tokens", where,
                "items[].text multiset %s != answer.values token multiset %s"
                % (sorted(multiset(tokens).elements()), sorted(multiset(flat).elements())),
            )
        for item in items or []:
            if isinstance(item, dict) and item.get("isCorrect") is not None:
                report.warn("rearrange-flag", where, "items[].isCorrect should be null for rearrangeWords")
                break
    elif kind == "matching":
        check_matching(items or [], values, where, report)
    elif kind == "trueFalse":
        if atype == "boolean":
            if "items" in ex and items and len(items) > 2:
                report.warn("tf-options", where, "trueFalse has %d items; expected one option" % len(items))
        elif atype == "choice" and not isinstance(values, list):
            report.error("tf-choice", where, "trueFalse with answer.type \"choice\" needs values as an array")
    elif kind == "dictation":
        report.warn(
            "dictation-as-exercise", where,
            "kind \"dictation\" is also a step type; a DictationStep item is the documented carrier",
        )

    if atype == "text":
        if not isinstance(values, list) or not values:
            report.error("text-answer-empty", where, "text answer needs a non-empty values array")
        else:
            for n, v in enumerate(values, 1):
                if not is_nonempty_str(v):
                    report.error("text-answer-blank", where, "answer.values[%d] is empty after trim" % (n - 1))


def check_matching(items, values, where: str, report: Report) -> None:
    """Both documented Answer.pairs shapes; flag any third."""
    if not isinstance(values, dict):
        report.error("matching-shape", where, "matching answer.values is not an object")
        return
    if not items:
        # Shape 2: domain-keyed. Compared literally key for key.
        if not values:
            report.error("matching-shape", where, "domain-keyed pairs answer has no keys")
        return
    keyed = [i for i in items if isinstance(i, dict) and i.get("matchKey") is not None]
    if len(keyed) != len(items):
        report.error(
            "matching-shape", where,
            "%d of %d items carry a matchKey; the item-based shape requires every item to"
            % (len(keyed), len(items)),
        )
        return
    match_keys = [i["matchKey"] for i in items]
    repeated = sorted(k for k, n in Counter(match_keys).items() if n > 1)
    if repeated:
        # DOC_DECISION: ARCHITECTURE.md s1 "Matching answers" says "every matchKey
        # group is used exactly once", but AnswerValue.pairs is graded by exact map
        # equality, so several items pointing at one matchKey grade correctly.
        # Warning, not error: the decoder accepts this and the shipped content relies
        # on it. The architecture owner must either fix the wording or fix the content.
        report.warn(
            "matching-reuse", where,
            "%d item(s) share a matchKey %s. ARCHITECTURE.md s1 says every matchKey is used "
            "exactly once; AnswerValue.pairs compares maps, so this grades correctly. "
            "Doc/decoder disagreement -- needs an owner decision"
            % (sum(match_keys.count(k) for k in repeated), repeated),
        )
    expected = {i["id"]: i["matchKey"] for i in items}
    if values != expected:
        report.error(
            "matching-answer", where,
            "answer maps %s but items require item.id -> item.matchKey = %s"
            % (dict(sorted(values.items())), dict(sorted(expected.items()))),
        )


def check_step(step, topic_id: str, lesson_id: str, lesson_level, index: LineIndex,
               rel: str, report: Report, corpus: Corpus, seen_step_ids: set) -> None:
    if not isinstance(step, dict):
        report.error("step-shape", index.at(None), "step is not an object")
        return
    stype = step.get("type")
    step_id = step.get("id")
    where = index.at(step_id if isinstance(step_id, str) else None)
    corpus.step_types[stype] += 1

    if not is_nonempty_str(step_id):
        report.error("step-id", where, "step has no id")
    elif step_id in seen_step_ids:
        report.error("step-id-dupe", where, "step id %r repeats inside lesson %r" % (step_id, lesson_id))
    else:
        seen_step_ids.add(step_id)

    if stype not in STEP_TYPES:
        report.error("step-type", where, "type %r is not a StepType case" % stype)
        return

    required, optional = STEP_PAYLOAD[stype]
    missing = sorted(required - set(step))
    if missing:
        report.error("step-payload", where, "%s step is missing required key(s) %s" % (stype, ", ".join(missing)))
    extra = unknown_keys(step, required | optional | {"id", "type"})
    if extra:
        report.warn("unknown-key", where, "%s step has unknown key(s) %s" % (stype, ", ".join(extra)))

    if stype == "video":
        check_video_clip(step.get("video"), where, report, corpus.video_sources)
    elif stype == "audio":
        check_audio_clip(step.get("audio"), where, index, report)
        if step.get("audio") is None:
            report.error("step-payload", where, "audio step has no audio clip")
    elif stype == "examples":
        check_examples(step.get("examples"), where, report)
    elif stype == "theory":
        if not is_nonempty_str(step.get("heading")):
            report.warn("theory-heading", where, "theory step has an empty heading")
        if not is_nonempty_str(step.get("body")):
            report.warn("theory-body", where, "theory step has an empty body")
        for n, rule in enumerate(step.get("rules") or [], 1):
            if not isinstance(rule, dict) or not {"title", "statement"} <= set(rule):
                report.error("rule-shape", where, "rules[%d] needs title and statement" % (n - 1))
            elif not is_nonempty_str(rule.get("statement")):
                report.error("rule-shape", where, "rules[%d].statement is empty" % (n - 1))
            else:
                check_examples(rule.get("examples"), where, report, prefix="rules[%d].examples" % (n - 1))
    elif stype == "dictation":
        items = step.get("items")
        if not isinstance(items, list) or not items:
            report.error("step-payload", where, "dictation step needs a non-empty items array")
        else:
            corpus.dictation_items += len(items)
            local: set = set()
            for n, item in enumerate(items, 1):
                if not isinstance(item, dict):
                    report.error("dictation-item", where, "items[%d] is not an object" % (n - 1))
                    continue
                dw = index.at(item.get("id") if isinstance(item.get("id"), str) else None)
                if not is_nonempty_str(item.get("id")):
                    report.error("dictation-item", dw, "dictation item has no id")
                elif item["id"] in local:
                    report.error("dictation-item", dw, "dictation item id %r repeats in this step" % item["id"])
                else:
                    local.add(item["id"])
                clip = item.get("audio")
                if not isinstance(clip, dict):
                    report.error("dictation-audio", dw, "dictation item has no audio clip")
                    continue
                check_audio_clip(clip, dw, index, report)
                if clip.get("kind") == "speech" and not is_nonempty_str(clip.get("text")):
                    report.error(
                        "dictation-audio", dw,
                        "DictationItem.expectedText is audio.text; empty text means an empty answer",
                    )
                elif clip.get("kind") != "speech":
                    report.error(
                        "dictation-audio", dw,
                        "kind %r needs no bundled assets — use speech" % clip.get("kind"),
                    )
    elif stype == "listening":
        check_audio_clip(step.get("audio"), where, index, report)
        exs = step.get("exercises")
        if not isinstance(exs, list) or not exs:
            report.error("step-payload", where, "listening step needs a non-empty exercises array")
            return
        for ex in exs:
            if not isinstance(ex, dict):
                continue
            if not isinstance(ex.get("audio"), dict):
                report.warn(
                    "listening-step-audio", index.at(ex.get("id")),
                    "listening step carries no step-level audio and this exercise has none either",
                )
            check_exercise(ex, topic_id, lesson_id, lesson_level, index, rel, report, corpus, "listening step")
    elif stype in ("exercises", "quiz"):
        key = "exercises" if stype == "exercises" else "questions"
        exs = step.get(key)
        if not isinstance(exs, list) or not exs:
            report.error("step-payload", where, "%s step needs a non-empty %s array" % (stype, key))
            return
        if stype == "quiz":
            corpus.quiz_questions += len(exs)
            pass_percent = step.get("passPercent")
            if pass_percent is not None and (not isinstance(pass_percent, (int, float)) or not 0 < pass_percent <= 100):
                report.error("pass-percent", where, "passPercent %r must be 1...100" % pass_percent)
        for ex in exs:
            check_exercise(ex, topic_id, lesson_id, lesson_level, index, rel, report, corpus, "%s step" % stype)
    elif stype == "summary":
        takeaways = step.get("takeaways")
        if not isinstance(takeaways, list) or not takeaways:
            report.error("step-payload", where, "summary step needs a non-empty takeaways array")
        else:
            for n, t in enumerate(takeaways, 1):
                if not is_nonempty_str(t):
                    report.error("takeaway", where, "takeaways[%d] is empty" % (n - 1))
    elif stype == "practice":
        ids = step.get("exerciseIDs")
        if not isinstance(ids, list) or not ids:
            report.error("step-payload", where, "practice step needs a non-empty exerciseIDs array")


def check_examples(examples, where: str, report: Report, prefix: str = "examples") -> None:
    if examples is None:
        return
    if not isinstance(examples, list):
        report.error("examples-shape", where, "%s is not an array" % prefix)
        return
    for n, ex in enumerate(examples, 1):
        if not isinstance(ex, dict):
            report.error("examples-shape", where, "%s[%d] is not an object" % (prefix, n - 1))
            continue
        if not is_nonempty_str(ex.get("id")):
            report.warn("example-id", where, "%s[%d] has no id" % (prefix, n - 1))
        if not is_nonempty_str(ex.get("en")):
            report.warn("example-en", where, "%s[%d].en is empty" % (prefix, n - 1))
        if not is_nonempty_str(ex.get("vi")):
            report.warn("example-vi", where, "%s[%d].vi is empty (vi fields are encouraged)" % (prefix, n - 1))


def check_topic(topic, rel: str, report: Report, corpus: Corpus, index: LineIndex) -> None:
    if not isinstance(topic, dict):
        report.error("topic-shape", rel, "top-level value is not an object")
        return
    stem = os.path.splitext(os.path.basename(rel))[0]
    corpus.topics += 1

    topic_id = topic.get("id")
    if topic_id != stem:
        report.error(
            "topic-id", "%s:1" % rel,
            "topic id %r does not match its filename stem %r" % (topic_id, stem),
        )
    elif not KEBAB.match(str(topic_id)):
        report.error("topic-id", "%s:1" % rel, "topic id %r is not kebab-case" % topic_id)
    if topic.get("kind") not in TOPIC_KINDS:
        report.error("topic-kind", "%s:1" % rel, "kind %r is not a TopicKind case" % topic.get("kind"))
    if topic.get("level") not in LEVELS:
        report.error("topic-level", "%s:1" % rel, "level %r is not a valid Level" % topic.get("level"))
    for key in ("title", "summary", "icon"):
        if not is_nonempty_str(topic.get(key)):
            report.error("topic-%s" % key, "%s:1" % rel, "%s missing or empty" % key)
    minutes = topic.get("estimatedMinutes")
    if minutes is not None and (not isinstance(minutes, int) or minutes <= 0):
        report.warn("topic-minutes", "%s:1" % rel, "estimatedMinutes %r should be a positive integer" % minutes)
    extra = unknown_keys(topic, {
        "id", "title", "kind", "level", "summary", "icon",
        "estimatedMinutes", "lessons",
    })
    if extra:
        report.warn("unknown-key", "%s:1" % rel, "topic has unknown key(s) %s" % ", ".join(extra))

    lessons = topic.get("lessons")
    if not isinstance(lessons, list) or not lessons:
        report.error("topic-lessons", "%s:1" % rel, "topic needs a non-empty lessons array")
        return

    for lesson in lessons:
        if not isinstance(lesson, dict):
            report.error("lesson-shape", "%s:1" % rel, "lesson is not an object")
            continue
        lesson_id = lesson.get("id")
        corpus.lessons += 1
        corpus.lesson_ids[lesson_id].append(rel)
        lw = index.at(lesson_id if isinstance(lesson_id, str) else None)
        if not is_nonempty_str(lesson_id):
            report.error("lesson-id", lw, "lesson has no id")
        elif not KEBAB.match(lesson_id):
            report.error("lesson-id", lw, "lesson id %r is not stable kebab-case" % lesson_id)
        if not is_nonempty_str(lesson.get("title")):
            report.error("lesson-title", lw, "lesson has no title")
        if not is_nonempty_str(lesson.get("summary")):
            report.warn("lesson-summary", lw, "lesson summary missing or empty")
        level = lesson.get("level")
        if level is not None and level not in LEVELS:
            report.error("lesson-level", lw, "level %r is not a valid Level" % level)
        resolved = level or topic.get("level")
        xp = lesson.get("xp")
        if xp is not None and (not isinstance(xp, int) or xp <= 0):
            report.error("lesson-xp", lw, "xp %r must be a positive integer" % xp)
        steps = lesson.get("steps")
        if not isinstance(steps, list) or not steps:
            report.error("lesson-steps", lw, "lesson needs a non-empty steps array")
            continue

        seen: set = set()
        types = [s.get("type") for s in steps if isinstance(s, dict)]
        for step in steps:
            check_step(step, topic_id, lesson_id, resolved, index, rel, report, corpus, seen)

        if lesson_id and corpus.drift.get(lesson_id):
            report.warn(
                "difficulty-drift", lw,
                "%d of this lesson's exercises carry a difficulty other than the lesson "
                "level %r: %s"
                % (
                    sum(corpus.drift[lesson_id].values()), resolved,
                    ", ".join("%s x%d" % (d, n) for d, n in sorted(corpus.drift[lesson_id].items())),
                ),
            )
            corpus.drift.pop(lesson_id, None)

        order = [STEP_ORDER.index(t) for t in types if t in STEP_ORDER]
        if order != sorted(order):
            for a in range(len(order) - 1):
                if order[a] > order[a + 1]:
                    corpus.step_order[rel][("%s before %s" % (types[a], types[a + 1]))] += 1
                    break
        if "summary" in types and types[-1] != "summary":
            report.warn("summary-position", lw, "summary is not the last step; only the last step gates completion")

        first_content = next((i for i, t in enumerate(types) if t in PRACTICE_CONTENT), None)
        for i, t in enumerate(types):
            if t in ("quiz", "summary"):
                if first_content is None:
                    report.warn(
                        "step-sequence", lw,
                        "lesson has a %r step but no exercises/dictation/listening/practice step at all"
                        % t,
                    )
                elif first_content > i:
                    report.warn("step-sequence", lw, "%r step comes before any practice content" % t)


# --- Vocabulary and IELTS ---------------------------------------------------


def check_vocabulary(path: str, report: Report) -> None:
    loaded = load_json(path, "vocabulary.json", report)
    if loaded is None:
        return
    deck = loaded.data
    if not isinstance(deck, dict):
        report.error("deck-shape", "vocabulary.json:1", "top-level value is not an object")
        return
    index = loaded.index
    if not is_nonempty_str(deck.get("id")):
        report.error("deck-id", "vocabulary.json:1", "deck has no id")
    if not is_nonempty_str(deck.get("title")):
        report.error("deck-title", "vocabulary.json:1", "deck has no title")
    words = deck.get("words")
    if not isinstance(words, list) or not words:
        report.error("deck-words", "vocabulary.json:1", "deck needs a non-empty words array")
        return
    seen: set = set()
    for word in words:
        if not isinstance(word, dict):
            report.error("word-shape", "vocabulary.json:1", "word is not an object")
            continue
        wid = word.get("id")
        where = index.at(wid if isinstance(wid, str) else None)
        if not is_nonempty_str(wid):
            report.error("word-id", where, "word has no id")
        elif wid in seen:
            report.error("word-id-dupe", where, "word id %r repeats in the deck" % wid)
        else:
            seen.add(wid)
        if not is_nonempty_str(word.get("word")):
            report.error("word-headword", where, "word field missing or empty")
        ipa = word.get("ipa")
        if not IPA.match(ipa or ""):
            report.error("word-ipa", where, "ipa %r is not wrapped in /.../" % ipa)
        if word.get("level") not in LEVELS:
            report.error("word-level", where, "level %r is not a valid Level" % word.get("level"))
        if not is_nonempty_str(word.get("meaning")):
            report.error("word-meaning", where, "meaning missing or empty")
        if not is_nonempty_str(word.get("example")):
            report.error("word-example", where, "example missing or empty")
        if word.get("exampleVI") is not None and not is_nonempty_str(word.get("exampleVI")):
            report.warn("word-exampleVI", where, "exampleVI present but empty")
        clip = word.get("audio")
        if not isinstance(clip, dict):
            report.error("word-audio", where, "audio missing or not an object")
        else:
            check_audio_clip(clip, where, index, report)
            if clip.get("kind") == "speech" and clip.get("text") != word.get("word"):
                report.error(
                    "word-audio", where,
                    "audio.text %r != word %r; TTS would say the wrong thing"
                    % (clip.get("text"), word.get("word")),
                )


def check_ielts(path: str, rel: str, report: Report, corpus: Corpus) -> None:
    loaded = load_json(path, rel, report)
    if loaded is None:
        return
    module = loaded.data
    if not isinstance(module, dict):
        report.error("module-shape", "%s:1" % rel, "top-level value is not an object")
        return
    index = loaded.index
    if not is_nonempty_str(module.get("id")):
        report.error("module-id", "%s:1" % rel, "module has no id")
    if module.get("skill") not in IELTS_SKILLS:
        report.error("module-skill", "%s:1" % rel, "skill %r is not an IELTSSkill case" % module.get("skill"))
    if not is_nonempty_str(module.get("title")):
        report.error("module-title", "%s:1" % rel, "module has no title")
    lessons = module.get("lessons")
    if not isinstance(lessons, list) or not lessons:
        report.error("module-lessons", "%s:1" % rel, "module needs a non-empty lessons array")
        return

    seen: set = set()
    for lesson in lessons:
        if not isinstance(lesson, dict):
            report.error("ielts-lesson-shape", "%s:1" % rel, "lesson is not an object")
            continue
        lid = lesson.get("id")
        where = index.at(lid if isinstance(lid, str) else None)
        if not is_nonempty_str(lid):
            report.error("ielts-lesson-id", where, "IELTS lesson has no id")
        elif lid in seen:
            report.error("ielts-lesson-dupe", where, "IELTS lesson id %r repeats" % lid)
        else:
            seen.add(lid)
        if not is_nonempty_str(lesson.get("title")):
            report.error("ielts-lesson-title", where, "IELTS lesson has no title")
        band = lesson.get("band")
        if band is not None and not BAND.match(str(band)):
            report.error("ielts-band", where, "band %r does not parse as a number" % band)
        transcript = lesson.get("transcript")
        if not isinstance(transcript, list):
            report.error("ielts-transcript", where, "transcript is missing or not an array")
        check_audio_clip(lesson.get("audio"), where, index, report)

        items = lesson.get("items")
        if not isinstance(items, list) or not items:
            report.error("ielts-items", where, "IELTS lesson needs a non-empty items array")
            continue
        instruction_text = " ".join(
            [str(lesson.get("title") or "")] + [str(i.get("instruction") or "") for i in items if isinstance(i, dict)]
        )
        qids: set = set()
        for item in items:
            if not isinstance(item, dict):
                report.error("ielts-item-shape", where, "question is not an object")
                continue
            qid = item.get("id")
            qw = index.at(qid if isinstance(qid, str) else None)
            corpus.ielts_questions += 1
            if not is_nonempty_str(qid):
                report.error("ielts-item-id", qw, "question has no id")
            elif qid in qids:
                report.error("ielts-item-dupe", qw, "question id %r repeats in lesson %r" % (qid, lid))
            else:
                qids.add(qid)
            kind = item.get("kind")
            if kind not in IELTS_KINDS:
                report.error(
                    "ielts-kind", qw,
                    "kind %r is not an IELTSQuestion.Kind case%s"
                    % (kind, " (it is an ExerciseKind — IELTSQuestion will not decode)" if kind in EXERCISE_KINDS else ""),
                )
            if not is_nonempty_str(item.get("prompt")):
                report.error("ielts-prompt", qw, "prompt missing or empty")
            if item.get("lessonID") not in (None, lid):
                report.error("ielts-lesson-id", qw, "lessonID %r != containing lesson %r" % (item.get("lessonID"), lid))
            answer = item.get("answer")
            if not isinstance(answer, dict) or answer.get("type") not in ANSWER_TYPES:
                report.error("ielts-answer", qw, "answer missing or has an unknown type")
            explanation = item.get("explanation")
            if not is_nonempty_str(explanation) or len(explanation.strip()) < 20:
                report.error("ielts-explanation", qw, "explanation missing, empty, or under 20 characters")
            if kind == "multipleChoice":
                opts = [o for o in (item.get("items") or []) if isinstance(o, dict)]
                correct = [o.get("id") for o in opts if o.get("isCorrect") is True]
                if len(opts) != 4:
                    report.error("ielts-mc-options", qw, "multipleChoice has %d options; IELTS requires exactly 4" % len(opts))
                if len(correct) != 1:
                    report.error("ielts-mc-correct", qw, "multipleChoice has %d correct options; exactly 1 required" % len(correct))
                values = (answer or {}).get("values")
                if isinstance(values, list) and sorted(values) != sorted(str(c) for c in correct):
                    report.error("ielts-mc-answer", qw, "answer.values %s != isCorrect ids %s" % (sorted(values), sorted(str(c) for c in correct)))
            if kind in ("mapLabeling", "diagramLabeling", "matching"):
                check_matching([o for o in (item.get("items") or []) if isinstance(o, dict)],
                                (answer or {}).get("values"), qw, report)

        if module.get("skill") == "listening":
            for a, b in QUESTION_RANGE.findall(instruction_text):
                if int(b) - int(a) + 1 != len(items):
                    report.warn(
                        "ielts-range", where,
                        "instruction says Questions %s-%s (%d) but the lesson has %d questions"
                        % (a, b, int(b) - int(a) + 1, len(items)),
                    )


# --- Driver -----------------------------------------------------------------


def main(argv: list[str]) -> int:
    quiet = "--quiet" in argv
    repo = os.getcwd()
    root = os.path.join(repo, ROOT)
    report = Report()
    corpus = Corpus()

    if not os.path.isdir(root):
        print("ERROR: content root not found: %s" % ROOT, file=sys.stderr)
        return 2

    # -- index ----------------------------------------------------------------
    listed: list[str] = []
    if not os.path.isfile(INDEX):
        report.error("index-missing", "content.json", "course index not found")
    else:
        loaded = load_json(INDEX, "content.json", report)
        if loaded is not None:
            index_data = loaded.data
            if not isinstance(index_data, dict):
                report.error("index-shape", "content.json:1", "top-level value is not an object")
            else:
                ids = index_data.get("topicIDs")
                if not isinstance(ids, list) or not ids:
                    report.error("index-topics", "content.json:1", "topicIDs missing or empty")
                else:
                    for n, tid in enumerate(ids, 1):
                        if not isinstance(tid, str) or not KEBAB.match(tid):
                            report.error("index-topic-id", "content.json:%d" % n, "topic id %r is not kebab-case" % tid)
                        listed.append(tid)
                    dupes = sorted(t for t, c in Counter(listed).items() if c > 1)
                    if dupes:
                        report.error("index-dupe", "content.json:1", "topicIDs repeats %s" % ", ".join(dupes))
                for key in ("id", "title", "description"):
                    if not is_nonempty_str(index_data.get(key)):
                        report.error("index-field", "content.json:1", "%s missing or empty" % key)
                modules = index_data.get("ieltsModuleIDs")
                if modules is not None and not isinstance(modules, list):
                    report.error("index-modules", "content.json:1", "ieltsModuleIDs must be an array")

    # -- topic files ----------------------------------------------------------
    present: set = set()
    if not os.path.isdir(TOPICS_DIR):
        report.error("topics-dir", "topics/", "topics directory not found")
    else:
        names = sorted(n for n in os.listdir(TOPICS_DIR) if n.endswith(".json"))
        if not names:
            report.error("topics-dir", "topics/", "no .json files")
        for name in names:
            tid = name[:-5]
            present.add(tid)
            rel = "topics/%s" % name
            loaded = load_json(os.path.join(TOPICS_DIR, name), rel, report)
            if loaded is None:
                # Another lane may be mid-write. Not a content defect; report and move on.
                report.warnings.append(
                    "%s:1 — [unparseable] SKIPPED: this file did not parse, so none of its "
                    "content was checked. Re-run the validator once the writing lane lands." % rel
                )
                continue
            check_topic(loaded.data, rel, report, corpus, loaded.index)
            if tid not in listed:
                report.warn(
                    "unlisted-topic", "%s:1" % rel,
                    "topics/%s.json is not listed in content.json topicIDs; ContentLibrary still "
                    "loads it (appended in file order) so the study order differs from the index" % tid,
                )
        for tid in listed:
            if tid not in present:
                report.error("missing-topic", "content.json", "topicIDs lists %r but topics/%s.json does not exist" % (tid, tid))

    # -- vocabulary -----------------------------------------------------------
    vocab_path = os.path.join(root, "vocabulary.json")
    if not os.path.isfile(vocab_path):
        report.error("vocab-missing", "vocabulary.json", "vocabulary deck not found")
    else:
        check_vocabulary(vocab_path, report)

    # -- IELTS ----------------------------------------------------------------
    ielts_files = sorted(n for n in os.listdir(root) if n.startswith("ielts") and n.endswith(".json"))
    if not ielts_files:
        report.warn("ielts-none", ROOT, "no IELTS module files found")
    for name in ielts_files:
        check_ielts(os.path.join(root, name), name, report, corpus)

    # -- corpus-wide ----------------------------------------------------------
    for ex_id, places in sorted(corpus.exercise_ids.items()):
        if ex_id is not None and len(places) > 1:
            report.error(
                "exercise-id-dupe", "content",
                "exercise id %r appears in %d files: %s" % (ex_id, len(places), "; ".join(places)),
            )
    for lesson_id, places in sorted(corpus.lesson_ids.items()):
        if lesson_id is not None and len(places) > 1:
            report.error(
                "lesson-id-dupe", "content",
                "lesson id %r appears in %d files: %s" % (lesson_id, len(places), "; ".join(places)),
            )

    for rel, pairs in sorted(corpus.step_order.items()):
        report.warn(
            "step-order", "%s:1" % rel,
            "%d lesson(s) break the s3 step sequence (theory -> video -> examples -> listening "
            "-> dictation -> practice -> quiz -> summary): %s"
            % (sum(pairs.values()), "; ".join("%s x%d" % (p, n) for p, n in pairs.most_common())),
        )

    unused = [k for k in EXERCISE_KINDS if k not in corpus.kinds]
    unknown_used = [k for k in corpus.kinds if k not in EXERCISE_KINDS]

    # -- output ---------------------------------------------------------------
    print("Content validation — %s" % ROOT)
    print("=" * 72)

    if report.errors:
        print("\nERRORS (%d)" % len(report.errors))
        print("-" * 72)
        for line in report.errors:
            print("  " + line)
        print("\n  by kind:")
        for kind, n in report.by_kind(report.errors).most_common():
            print("    %-26s %d" % (kind, n))
    else:
        print("\nERRORS: none")

    if not quiet:
        if report.warnings:
            print("\nWARNINGS (%d)" % len(report.warnings))
            print("-" * 72)
            for line in report.warnings:
                print("  " + line)
            print("\n  by kind:")
            for kind, n in report.by_kind(report.warnings).most_common():
                print("    %-26s %d" % (kind, n))
        else:
            print("\nWARNINGS: none")
    elif report.warnings:
        print("\nWARNINGS: %d (hidden by --quiet)" % len(report.warnings))

    print("\nTOTALS")
    print("-" * 72)
    rows = [
        ("topic files", corpus.topics),
        ("lessons", corpus.lessons),
        ("exercises (topic corpus)", corpus.exercises),
        ("quiz questions", corpus.quiz_questions),
        ("dictation items", corpus.dictation_items),
        ("IELTS questions", corpus.ielts_questions),
        ("distinct ExerciseKinds used", len([k for k in corpus.kinds if k in EXERCISE_KINDS])),
        ("ExerciseKinds never used", len(unused)),
        ("lesson steps", sum(corpus.step_types.values())),
    ]
    for label, value in rows:
        print("  %-34s %d" % (label, value))

    print("\n  step types:")
    for name in STEP_TYPES:
        print("    %-34s %d" % (name, corpus.step_types[name]))
    for name, n in sorted(corpus.step_types.items()):
        if name not in STEP_TYPES:
            print("    %-34s %d  (UNKNOWN)" % (name, n))

    print("\n  ExerciseKind coverage (of %d cases):" % len(EXERCISE_KINDS))
    for name in EXERCISE_KINDS:
        n = corpus.kinds[name]
        print("    %-28s %5d %s" % (name, n, "" if n else "UNUSED"))
    if unused:
        print("\n  UNUSED ExerciseKinds: %s" % ", ".join(unused))
    else:
        print("\n  UNUSED ExerciseKinds: none — every case in ExerciseKind is used")
    if unknown_used:
        print("  kinds outside ExerciseKind: %s" % ", ".join(sorted(unknown_used)))

    print("\n  audio (the app ships zero media assets):")
    print("    audio-requiring exercises with speech text  %d / %d"
          % (corpus.audio_required_with_speech, corpus.audio_required_total))

    print("\n  VideoClip source types:")
    if not corpus.video_sources:
        print("    none committed")
    for name, n in sorted(corpus.video_sources.items()):
        print("    %-34s %d" % (name, n))
    remote = corpus.video_sources.get("remote", 0)
    print("    remote clips: %d (ARCHITECTURE.md s1 says ship .none — 0 expected)" % remote)

    print("\n" + "=" * 72)
    if report.errors:
        print("FAIL: %d error(s), %d warning(s)" % (len(report.errors), len(report.warnings)))
        return 1
    print("PASS: %d warning(s), no errors" % len(report.warnings))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
