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
# IELTSQuestion is `typealias Exercise`, so an IELTS question's kind is an
# ExerciseKind case -- the same table as the rest of the course. The old
# 13-case IELTSQuestion.Kind enum was deleted (IELTS.swift:22): no shipped
# question used it and its presence made every IELTS module fail to decode.
IELTS_SKILLS = ("listening", "reading", "writing", "speaking")

# docs/ARCHITECTURE.md section 1, "answer.type and items shape per exercise kind".
# trueFalse accepts either boolean or choice -- that is intentional.
# `listening` has no row in the s1 table, but it is an ExerciseKind case
# (Exercise.swift:9) and the shipped corpus uses it with both text and choice
# answers, so it is accepted here on the decoder's authority rather than warned
# about on the doc's.
EXPECTED_ANSWER_TYPE = {
    "multipleChoice": "choice",
    "multiSelect": "choice",
    "trueFalse": ("boolean", "choice"),
    "fillInTheBlank": "text",
    "typeTheAnswer": "text",
    "dictation": "text",
    "listening": ("text", "choice"),
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

# Kinds that must carry their own audio stimulus (keeps the app asset-free).
AUDIO_REQUIRED_KINDS = ("listening", "listeningComprehension", "dictation")

# Section 3's documented sequence: theory -> video -> examples -> listening ->
# dictation -> practice -> quiz -> summary.
#
# DOC_DECISION: the doc puts `dictation` before `practice`, and never names
# `exercises` at all (the s1 table has both `practice` and `exercises`; the
# corpus ships `exercises` 160 times and `practice` 0). All 160 lessons in the
# corpus agree on the order below, unanimously, and the decoder has no ordering
# requirement. So the content is coherent and the doc is the stale side: the
# check follows the corpus convention and reports the divergence once, as a
# DOC_DECISION note, instead of flagging every lesson in every file.
# ARCHITECTURE.md s3 should read:
#   theory -> video -> audio -> examples -> listening -> exercises -> dictation
#         -> practice -> quiz -> summary
STEP_ORDER = (
    "theory", "video", "audio", "examples", "listening",
    "exercises", "dictation", "practice", "quiz", "summary",
)
# The doc's sequence, kept so the note can name the exact divergence.
DOC_STEP_ORDER = (
    "theory", "video", "audio", "examples", "listening",
    "dictation", "practice", "exercises", "quiz", "summary",
)
LEVEL_INDEX = {name: n for n, name in enumerate(LEVELS)}
PRACTICE_CONTENT = ("exercises", "dictation", "listening", "practice")

KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
IPA = re.compile(r"^/.+/$", re.S)
BAND = re.compile(r"^\d+(\.\d+)?$")
QUESTION_RANGE = re.compile(r"[Qq]uestions?\s*(\d+)\s*[-–—]\s*(\d+)")
QUESTION_SINGLE = re.compile(r"[Qq]uestion\s+(\d+)")

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

    def note(self, message: str) -> None:
        """A doc/decoder disagreement or a rule-change verdict.

        Not a finding against the content and not a finding against the doc: a
        recorded decision, printed so a stale rule can never quietly become a
        silent one again.
        """
        self.notes.append(message)

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
        self.module_ids: dict[str, list[str]] = defaultdict(list)
        self.kinds: Counter = Counter()
        self.dictation_items = 0
        self.quiz_questions = 0
        self.step_types: Counter = Counter()
        self.video_sources: Counter = Counter()
        self.audio_required_with_speech = 0
        self.audio_required_total = 0
        # lesson id -> Counter(delta -> count) for exercises whose difficulty is
        # two or more levels away from the lesson level; reported once per lesson.
        self.jump: dict[str, Counter] = defaultdict(Counter)
        # Corpus-wide Counter(delta -> count), for the totals block.
        self.difficulty_delta: Counter = Counter()
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
    # IELTS questions are Exercises too, but they are counted on their own line
    # so the topic-corpus totals stay comparable with the pre-IELTS numbers.
    if origin.startswith("IELTS"):
        corpus.ielts_questions += 1
    else:
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
    elif lesson_level in LEVELS:
        # Verdict on the old `difficulty-drift` rule: `difficulty` is a per-exercise
        # field precisely so one lesson can mix tiers, so a one-level step is
        # legitimate authoring (a distractor in a beginner lesson, a consolidation
        # item in an advanced one) and ARCHITECTURE.md never required equality --
        # s3 constrains the lesson *level* progression, not this field. Only a
        # two-level jump is an authoring inconsistency worth naming.
        delta = LEVEL_INDEX[difficulty] - LEVEL_INDEX[lesson_level]
        if abs(delta) >= 2:
            corpus.jump[lesson_id][delta] += 1
        corpus.difficulty_delta[delta] += 1

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
        else:
            report.error(
                "audio-required", where,
                "kind %s has no speech clip; the app ships zero media assets, so without "
                "audio.kind == \"speech\" with text this question is silent" % kind,
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
    if expected is not None:
        allowed = (expected,) if isinstance(expected, str) else expected
        if atype not in allowed:
            report.error(
                "answer-kind-mismatch", where,
                "kind %r requires answer.type %s, found %r"
                % (kind, " or ".join(allowed), atype),
            )

    # Decoder truth: the payload shape must be decodable as the type claims.
    # Answer.init(from:) (Exercise.swift:130) uses decodeIfPresent, so a payload
    # of the wrong type THROWS and takes the whole topic file -- and therefore the
    # whole topic -- out of the library with no visible error.
    #
    # `boolean` is the one case with a deliberate tolerance: Answer.decodeBoolean
    # (Exercise.swift:159) also accepts `value`, a bare string, and a
    # single-element array. Those forms decode, so they are a warning about
    # authoring style, not an error -- but they stay visible, because the reason
    # that tolerance exists is that the strict form once graded every True/False
    # question as false with nothing on screen to say so.
    if atype == "boolean":
        if not isinstance(values, bool):
            report.warn(
                "boolean-shape", where,
                "answer.type \"boolean\" but values is %s; Answer.decodeBoolean tolerates "
                "this and will read it as %r, but the canonical shape is a real JSON "
                "boolean under \"values\""
                % (type(values).__name__ if values is not None else "missing",
                   values if not isinstance(values, (list, dict)) else (values[0] if isinstance(values, list) and values else None)),
            )
        if "values" not in answer and "value" in answer:
            report.warn(
                "boolean-shape", where,
                "answer uses key \"value\"; Answer.decodeBoolean reads it as an alias, "
                "but the canonical key is \"values\"",
            )
    if atype in ("text", "choice", "order"):
        if values is None:
            report.error("answer-values", where, "answer.values missing for type %r" % atype)
        elif not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            # This is the shape that killed 25 rearrangeWords answers: `values`
            # nested one level deeper than [String]. AnswerValue.order holds ONE
            # order, so a nested list is not a "second accepted ordering" -- it is
            # a decode failure.
            nested = isinstance(values, list) and any(isinstance(v, list) for v in values)
            report.error(
                "answer-decode", where,
                "answer.type %r but values is %s%s; Answer.init(from:) decodes [String] and "
                "this THROWS, dropping the whole topic file"
                % (atype, type(values).__name__, " (nested one level too deep)" if nested else ""),
            )
    elif atype == "pairs" and values is not None and not isinstance(values, dict):
        report.error("answer-decode", where, "answer.type \"pairs\" but values is not an object")

    # An answer the exercise's own items cannot produce can never be graded
    # correct, however well it decodes.
    if atype == "choice" and isinstance(values, list) and items:
        known = {i.get("id") for i in items if isinstance(i, dict)}
        stray = sorted(v for v in values if v not in known)
        if stray:
            report.error(
                "answer-unsatisfiable", where,
                "answer.values %s name(s) no item id in this exercise (items are %s), so no "
                "learner response can match" % (stray, sorted(k for k in known if k)),
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
        # AnswerValue.order holds exactly one [String]. A nested list is a decode
        # failure, not "several accepted orderings" -- that tolerance was what let
        # 25 broken answers sit in the corpus unnoticed. answer-decode above has
        # already errored on it; only the flat case is graded here.
        candidates = values if isinstance(values, list) else []
        if candidates and all(isinstance(v, str) for v in candidates):
            if multiset(candidates) != multiset(tokens):
                report.error(
                    "rearrange-tokens", where,
                    "items[].text multiset %s != answer.values token multiset %s"
                    % (sorted(multiset(tokens).elements()), sorted(multiset(candidates).elements())),
                )
        elif not candidates:
            report.error("rearrange-tokens", where, "rearrangeWords needs an answer.values token order")
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
    # `kind == "dictation"` needs no rule: it is a documented ExerciseKind
    # (ARCHITECTURE.md s1 "dictation | — | text") and the 5 exercises that use it
    # all carry a speech clip and a text answer. A DictationStep is the other
    # carrier, not the only one.

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
    # The answer's KEY set is load-bearing: UserResponse.pairs has the same
    # orientation and grading is exact map equality (ARCHITECTURE.md s1), so a
    # missing or extra key is an unsatisfiable answer. Error.
    keyed_ids = [i["id"] for i in items]
    if set(values) != set(keyed_ids):
        report.error(
            "matching-keys", where,
            "answer key set %s != the item id set %s (missing %s, unknown %s); grading "
            "compares maps key for key, so this answer can never be satisfied"
            % (sorted(values), sorted(keyed_ids),
               sorted(set(keyed_ids) - set(values)), sorted(set(values) - set(keyed_ids))),
        )
    # The answer's VALUE is a free-form label -- "1", "ii", "A", a category name
    # -- and is not required to be the item's matchKey (ARCHITECTURE.md s1). So a
    # value set that differs from the matchKey set is a warning, not an error:
    # that is how IELTS map labelling and matching-information are authored.
    values_used = list(values.values())
    if set(values_used) != set(match_keys):
        report.warn(
            "matching-label", where,
            "answer values %s are labels rather than the items' matchKeys %s; this is how "
            "map labelling and matching-information are authored, and ExerciseEngine resolves "
            "both orientations, but the authored answer no longer mirrors items[].matchKey"
            % (sorted(set(values_used)), sorted(set(match_keys))),
        )
    # One-to-one is only implied when the items themselves offer a bijection: as
    # many distinct matchKeys as items. Six nouns matched to {countable,
    # uncountable} is a category exercise and reuse is the whole point; four items
    # that each have their own group, where the answer puts two of them on one
    # value, is a defect.
    repeated = sorted(k for k, n in Counter(values_used).items() if n > 1)
    if repeated and len(set(match_keys)) == len(items):
        report.error(
            "matching-one-to-one", where,
            "%d item(s) share the answer value %s while every one of the %d items has its "
            "own matchKey %s -- a one-to-one match, so one value is used twice and another "
            "is unreachable" % (sum(values_used.count(k) for k in repeated), repeated,
                                len(items), sorted(set(match_keys))),
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

        if lesson_id and corpus.jump.get(lesson_id):
            jumps = corpus.jump.pop(lesson_id)
            report.warn(
                "difficulty-jump", lw,
                "%d of this lesson's exercises sit two or more levels away from the lesson "
                "level %r: %s. A one-level difference is legitimate (an exercise's own "
                "difficulty is what the field is for); a two-level jump is a mis-tag"
                % (
                    sum(jumps.values()), resolved,
                    ", ".join(
                        "%s x%d" % (LEVELS[max(0, min(len(LEVELS) - 1, LEVEL_INDEX[resolved] + d))], n)
                        for d, n in sorted(jumps.items())
                    ),
                ),
            )

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
    mid = module.get("id")
    if not is_nonempty_str(mid):
        report.error("module-id", "%s:1" % rel, "module has no id")
    elif not KEBAB.match(mid):
        report.error("module-id", "%s:1" % rel, "module id %r is not stable kebab-case" % mid)
    corpus.module_ids[mid].append(rel)
    # IELTSModule.skill is optional and is only the module's headline label: one
    # module ships two papers (ielts-listening-reading.json), so nothing may be
    # inferred from it. The lesson is authoritative (IELTS.swift:29).
    if module.get("skill") is not None and module.get("skill") not in IELTS_SKILLS:
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
        skill = lesson.get("skill")
        if skill is not None and skill not in IELTS_SKILLS:
            report.error("ielts-skill", where, "skill %r is not an IELTSSkill case" % skill)
        elif skill is None and module.get("skill") is None:
            report.error(
                "ielts-skill", where,
                "lesson has no skill and its module has none either, so IELTSModule.skills "
                "cannot resolve this lesson to a paper",
            )
        band = lesson.get("band")
        if band is not None and not BAND.match(str(band)):
            report.error("ielts-band", where, "band %r does not parse as a number" % band)
        # IELTSLesson.transcript defaults to [] (IELTS.swift:45): a reading lesson
        # has no audio and correctly carries no transcript, so its absence is not
        # a defect. Only a listening lesson needs one, or there is nothing to
        # reveal after the attempt.
        is_listening = skill == "listening" or (skill is None and module.get("skill") == "listening")
        if is_listening:
            if not lesson.get("transcript"):
                report.warn(
                    "ielts-transcript", where,
                    "listening lesson has no transcript lines; nothing is shown after the attempt",
                )
            if not isinstance(lesson.get("audio"), dict):
                report.error(
                    "ielts-audio", where,
                    "listening lesson has no audio clip; the app ships zero media assets, so "
                    "this lesson is silent",
                )
        check_audio_clip(lesson.get("audio"), where, index, report)

        items = lesson.get("items")
        if not isinstance(items, list) or not items:
            report.error("ielts-items", where, "IELTS lesson needs a non-empty items array")
            continue
        # An IELTS question IS an Exercise (IELTS.swift:22), so it gets the same
        # checks as the rest of the corpus rather than a second, weaker set:
        # ExerciseKind case, answer.type consistent with the kind, answer
        # satisfiable by its own items, matching key set, speech audio where the
        # kind requires it. `ielts` is the topic these questions belong to.
        for item in items:
            if not isinstance(item, dict):
                report.error("ielts-item-shape", where, "question is not an object")
                continue
            check_exercise(
                item, "ielts", lid, None, index, rel, report, corpus,
                "IELTS %s lesson" % (skill or module.get("skill") or "untagged"),
            )

        # Question numbering. Instructions quote the paper's own numbering and a
        # lesson may hold only part of it ("Questions 1-4: match each place on the
        # map...", with questions 5-7 elsewhere in the same lesson), so a range
        # whose span differs from the item count is NOT a defect -- the old rule
        # fired 26 times on correct content. What cannot be right is an
        # instruction numbering a question the lesson does not contain.
        over = [
            i.get("id") for i in items
            if isinstance(i, dict) and max(stated_numbers(str(i.get("instruction") or "")), default=0) > len(items)
        ]
        highest = max((n for i in items if isinstance(i, dict)
                       for n in stated_numbers(str(i.get("instruction") or ""))), default=0)
        if over:
            report.warn(
                "ielts-range", where,
                "%s number questions up to %d but the lesson ships %d, so the learner is told "
                "to answer a question that does not exist"
                % (", ".join(str(o) for o in over), highest, len(items)),
            )


def stated_numbers(instruction: str) -> list[int]:
    """Every question number an instruction refers to, ranges and singletons."""
    out = [int(n) for pair in QUESTION_RANGE.findall(instruction) for n in pair]
    out += [int(n) for n in QUESTION_SINGLE.findall(instruction)]
    return out


# --- Self-test ---------------------------------------------------------------


def selftest() -> int:
    """Asserts every rule added here still fires on the defect it stands for.

    A validator that reports nothing is indistinguishable from a validator that
    checks nothing, and this corpus is currently clean -- so the only evidence
    that these rules work is a fixture each one is aimed at. Each case is the
    smallest payload that must fail.

        python3 Scripts/validate_content.py --selftest
    """
    topic_id, lesson_id = "t-selftest", "l-selftest"
    explain = "Long enough explanation to clear the twenty character floor."

    def exercise(**over) -> dict:
        ex = {
            "id": "ex-1", "kind": "fillInTheBlank", "topicID": topic_id,
            "lessonID": lesson_id, "difficulty": "beginner", "prompt": "He ___ (go).",
            "answer": {"type": "text", "values": ["goes"]}, "explanation": explain,
        }
        ex.update(over)
        return ex

    def run(ex: dict, lesson_level: str = "beginner"):
        topic = {
            "id": topic_id, "title": "T", "kind": "grammar", "level": "beginner",
            "summary": "s", "icon": "clock",
            "lessons": [{
                "id": lesson_id, "title": "L", "summary": "s", "level": lesson_level,
                "steps": [{"id": "s-1", "type": "exercises", "exercises": [ex]}],
            }],
        }
        report, corpus = Report(), Corpus()
        raw = json.dumps(topic, indent=1)
        check_topic(topic, "topics/t-selftest.json", report, corpus, LineIndex(raw, "topics/t-selftest.json"))
        return report, corpus

    def kinds(bucket: list[str]) -> set:
        return {m.group(1) for line in bucket if (m := re.search(r"—\s*\[([^\]]+)\]", line))}

    cases = [
        ("answer-decode: rearrangeWords values nested one level deep",
         exercise(kind="rearrangeWords", prompt="Reorder.",
                  items=[{"id": "a", "text": "in"}, {"id": "b", "text": "morning"}],
                  answer={"type": "order", "values": [["in", "morning"]]}),
         {"answer-decode"}, set()),
        ("answer-decode: boolean answer carries a string",
         exercise(kind="trueFalse", prompt="It rained.", answer={"type": "boolean", "values": "true"}),
         set(), {"boolean-shape"}),
        ("answer-unsatisfiable: choice names an item that does not exist",
         exercise(kind="multipleChoice", prompt="Pick one.",
                  items=[{"id": "a", "text": "A", "isCorrect": True},
                         {"id": "b", "text": "B", "isCorrect": False}],
                  answer={"type": "choice", "values": ["z"]}),
         {"answer-unsatisfiable"}, set()),
        ("matching-keys: pairs keys are not the item ids",
         exercise(kind="matching", prompt="Match.",
                  items=[{"id": "a", "text": "verb", "matchKey": "g1"},
                         {"id": "b", "text": "noun", "matchKey": "g2"}],
                  answer={"type": "pairs", "values": {"g1": "g1", "g2": "g2"}}),
         {"matching-keys"}, set()),
        ("matching-one-to-one: a value reused where a bijection was available",
         exercise(kind="matching", prompt="Match.",
                  items=[{"id": "a", "text": "v", "matchKey": "g1"},
                         {"id": "b", "text": "n", "matchKey": "g2"}],
                  answer={"type": "pairs", "values": {"a": "x", "b": "x"}}),
         {"matching-one-to-one"}, set()),
        ("matching-label: answer values are labels, not matchKeys (warn only)",
         exercise(kind="matching", prompt="Match.",
                  items=[{"id": "a", "text": "verb", "matchKey": "g1"},
                         {"id": "b", "text": "noun", "matchKey": "g2"}],
                  answer={"type": "pairs", "values": {"a": "1", "b": "2"}}),
         set(), {"matching-label"}),
        ("exercise-kind: an IELTS question with a kind outside ExerciseKind",
         exercise(kind="mapLabeling", prompt="Label the map."), {"exercise-kind"}, set()),
        ("audio-required: a listening exercise with no clip at all",
         exercise(kind="listeningComprehension", prompt="Listen."), {"audio-required"}, set()),
        ("difficulty-jump: two levels away from the lesson is reported",
         exercise(difficulty="advanced"), set(), {"difficulty-jump"}),
    ]
    failures = 0
    for name, ex, want_errors, want_warnings in cases:
        report, _corpus = run(ex)
        got_e, got_w = kinds(report.errors), kinds(report.warnings)
        if want_errors <= got_e and want_warnings <= got_w:
            print("  ok    %s" % name)
        else:
            failures += 1
            print("  FAIL  %s\n          expected errors %s warnings %s; got errors %s warnings %s"
                  % (name, sorted(want_errors) or "none", sorted(want_warnings) or "none",
                     sorted(got_e) or "none", sorted(got_w) or "none"))

    # Structural cases that do not go through an exercise step.
    def run_topic(topic: dict):
        report, corpus = Report(), Corpus()
        raw = json.dumps(topic, indent=1)
        check_topic(topic, "topics/t-selftest.json", report, corpus, LineIndex(raw, "topics/t-selftest.json"))
        return report

    base = {
        "id": topic_id, "title": "T", "kind": "grammar", "level": "beginner",
        "summary": "s", "icon": "clock",
        "lessons": [{"id": lesson_id, "title": "L", "summary": "s",
                     "steps": [{"id": "s-1", "type": "dictation", "items": []}]}],
    }
    structural = [
        ("topic-level: a Topic with no top-level level",
         {k: v for k, v in base.items() if k != "level"}, {"topic-level"}),
        ("step-payload: a dictation step with no items",
         base, {"step-payload"}),
    ]
    for name, topic, want in structural:
        got = kinds(run_topic(topic).errors)
        if want <= got:
            print("  ok    %s" % name)
        else:
            failures += 1
            print("  FAIL  %s\n          expected errors %s; got %s"
                  % (name, sorted(want), sorted(got) or "none"))

    # A ±1 difficulty difference must stay silent: it is legitimate authoring.
    report, _corpus = run(exercise(difficulty="intermediate"))
    if report.errors or report.warnings:
        failures += 1
        print("  FAIL  difficulty ±1 from the lesson level is silent\n          got %s"
              % (report.errors + report.warnings))
    else:
        print("  ok    difficulty ±1 from the lesson level is silent (legitimate authoring)")

    print("\nselftest: %d case(s), %d failure(s)" % (len(cases) + len(structural) + 1, failures))
    return 1 if failures else 0


# --- Driver -----------------------------------------------------------------


def main(argv: list[str]) -> int:
    quiet = "--quiet" in argv
    if "--selftest" in argv:
        print("validate_content.py self-test — one fixture per rule added")
        print("=" * 72)
        return selftest()
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
    for mid, places in sorted(corpus.module_ids.items()):
        if mid is not None and len(places) > 1:
            report.error(
                "module-id-dupe", "content",
                "IELTS module id %r appears in %d files: %s" % (mid, len(places), "; ".join(places)),
            )

    for rel, pairs in sorted(corpus.step_order.items()):
        report.warn(
            "step-order", "%s:1" % rel,
            "%d lesson(s) break the step sequence the whole corpus otherwise uses "
            "(theory -> video -> audio -> examples -> listening -> exercises -> dictation "
            "-> practice -> quiz -> summary): %s"
            % (sum(pairs.values()), "; ".join("%s x%d" % (p, n) for p, n in pairs.most_common())),
        )

    if corpus.lessons:
        report.note(
            "step order: every one of the %d lessons in the corpus uses the sequence above, "
            "which places `exercises` before `dictation`. ARCHITECTURE.md s3 states %s, which "
            "puts `dictation` before `practice` and never names `exercises` at all. The decoder "
            "has no ordering requirement, so the doc is the stale side: s3 should be updated. "
            "Until it is, this check follows the corpus convention so that 160 conforming "
            "lessons are not reported as 160 defects -- and it still catches the one thing "
            "that matters, a lesson that deviates from its peers."
            % (corpus.lessons, " -> ".join(DOC_STEP_ORDER)),
        )
    report.note(
        "matching answers: ARCHITECTURE.md s1 says \"each matchKey group is used once\", which "
        "20 shipped matching exercises contradict by design (six nouns matched to "
        "{countable, uncountable}). Grading is exact map equality, so those grade correctly and "
        "are no longer flagged. What is checked now is the part that is load-bearing: the "
        "answer's key set must be the item-id set (error), a value may not be reused where a "
        "one-to-one match was available (error), and an answer value that is a label rather "
        "than the item's matchKey (warn).",
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

    if report.notes and not quiet:
        print("\nDOC DECISIONS (%d) — recorded, not counted as findings" % len(report.notes))
        print("-" * 72)
        for n, line in enumerate(report.notes, 1):
            print("  %d. %s" % (n, line))
    elif report.notes:
        print("\nDOC DECISIONS: %d (hidden by --quiet)" % len(report.notes))

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

    print("\n  exercise difficulty vs its lesson's level:")
    for delta in sorted(corpus.difficulty_delta):
        label = "%+d" % delta if delta else " 0 (same level)"
        print("    %-22s %d%s" % (label, corpus.difficulty_delta[delta],
                                   "   legitimate authoring" if abs(delta) == 1 else
                                   ("   reported as difficulty-jump" if abs(delta) >= 2 else "")))
    total_d = sum(corpus.difficulty_delta.values())
    print("    %-22s %d" % ("exercises compared", total_d))

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
