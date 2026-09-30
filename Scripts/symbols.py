#!/usr/bin/env python3
"""Static Swift symbol index for the Small-APP repo.

There is no Swift toolchain on this host, so this stands in for the first
compiler pass: it finds redeclarations that cannot possibly link, and type
references that resolve to nothing anywhere in the repo.

IMPORTANT: a clean run is NOT evidence the code compiles. This script is a
regex-and-heuristic index. It cannot see overload resolution, generic
constraints, protocol conformance, actor isolation, access control, or any
type-check rule. Use it to find conflicts, never to declare victory.

Usage: python3 Scripts/symbols.py [-v]
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODULE_ROOTS = [
    ("App", os.path.join(ROOT, "App")),
    ("EnglishCore", os.path.join(ROOT, "Packages/EnglishCore/Sources/EnglishCore")),
    ("EnglishStore", os.path.join(ROOT, "Packages/EnglishStore/Sources/EnglishStore")),
]

# Swift type decls we know how to recognise. `struct X`, `final class X`,
# `@Model final class X`, `indirect enum X`, `private struct X`, ...
DECL_RE = re.compile(
    r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|internal|private|fileprivate|open|final|indirect|static|package)\s+)*"
    r"(struct|class|enum|actor|protocol|extension|typealias)\s+"
    r"([A-Z_][A-Za-z0-9_]*)"
)

TYPE_KINDS = ("struct", "class", "enum", "actor", "protocol", "extension", "typealias")

# `init(...)` / `init?(...)` / `init!(...)`, plus `required`/`override`/`convenience`.
INIT_RE = re.compile(
    r"^\s*(?:(?:public|internal|private|fileprivate|required|override|convenience|final)\s+)*"
    r"init[?!]?\s*(?:<[^>]*>)?\s*\(([^)]*)\)"
)

IMPORT_RE = re.compile(r"^\s*(?:@testable\s+)?import\s+(?:struct|class|enum|func|var|let|protocol|typealias|\s)*([A-Za-z_][A-Za-z0-9_.]*)")
EXPORT_RE = re.compile(r"^\s*@_exported\s+import\s+([A-Za-z_][A-Za-z0-9_.]*)")

# Members of a local namespace. Split by arity of the token they produce so we
# can tell a static token bucket (Radius.card) from an instance member.
MEMBER_RE = re.compile(
    r"^\s*(?:(?:public|internal|private|fileprivate|final|@objc|@\w+)\s+)*"
    r"(static\s+)?(?:let|var|func|subscript|typealias|case)\s+([A-Za-z_][A-Za-z0-9_]*)"
)

# Identifiers we must not report: Swift stdlib + the frameworks this app uses.
KNOWN = set("""
Any AnyObject AnyHashable Array Bool Character Codable Comparable CustomStringConvertible
Decodable Decoder Double Encodable Encoder Equatable Error Float Float32 Float64 Hashable
Hasher Identifiable Int Int8 Int16 Int32 Int64 Never Optional Range RawRepresentable
Result Self Sequence Set String Substring Task TimeInterval UInt UInt8 UInt16 UInt32 UInt64
UUID Void Void FloatingPoint BinaryInteger SignedInteger UnsignedInteger Strideable Collection
Comparable CaseIterable Encodable Codable AnyObject KeyPath Predicate Snapshotting
Sendable Duration Clock ContinuousClock SuspendingClock Instant Milliseconds Seconds
Tweenable Animatable Numeric Stride Comparable OptionSet ExpressibleByIntegerLiteral
ExpressibleByStringLiteral ExpressibleByFloatLiteral ExpressibleByArrayLiteral
ExpressibleByDictionaryLiteral ExpressibleByNilLiteral
ArraySlice KeyValuePairs ClosedRange UnboundedRange PartialRangeFrom PartialRangeThrough
UnsafeMutablePointer OpaquePointer Enumerator
Date Data URL UUID IndexPath IndexSet Notification UserDefaults Bundle FileManager
JSONDecoder JSONEncoder JSONSerialization Locale Calendar DateFormatter DateComponents
DateIntervalFormatter NumberFormatter IndexSet CharacterSet Scanner OperationQueue
DispatchQueue DispatchTime ProcessInfo TimeZone Calendar
TextDocument NSDictionary NSString NSNumber NSArray NSSet NSError NSLock NSObject
AffineTransform NSLayoutConstraint NSRange
SwiftUI App View Text Image Button Toggle TextField SecureField TextEditor Picker
Section Form List ScrollView LazyVStack LazyHStack VStack HStack ZStack Grid GridRow GridItem
Spacer Divider NavigationStack NavigationLink NavigationView NavigationSplitView NavigationPath
TabView Color Font Angle Edge EdgeInsets GeometryReader Path Shape Circle Capsule
Rectangle RoundedRectangle Ellipse Line Polygon LinearGradient RadialGradient AngularGradient
Material EmptyView AnyShape ScaledMetric ViewThatFits Label Gauge GaugeStyle
ProgressView Slider Stepper Menu Picker ContentUnavailableView Link ShareLink
UIViewControllerRepresentable UIViewRepresentable UIViewController UIImage UIImageView UILabel
UIButton UIColor UIFont UIView UIViewController UIAlertController UIImpactFeedbackGenerator
UINotificationFeedbackGenerator UISelectionFeedbackGenerator UIScreen UIFontDescriptor
UITraitCollection UIApplication UIScene UIAccessibility UIBezierPath UIEvent UITouch
UIHostingController UIVisualEffectView UIModalPresentationStyle UIUserInterfaceStyle
UIProgressView UIActivityIndicatorView UITableView UICollectionView UIScrollView
UISwipeGestureRecognizer UITapGestureRecognizer UIKeyboardType UIReturnKeyType
UIScrollViewContentInsetAdjustmentBehavior UIUserInterfaceIdiom
UIKit UIApplicationDelegate UIWindowSceneDelegate Scene Window AppDelegate
UIAppearance UITextField UIAccessibilityTraits UIAccessibilityCustomAction
AVFoundation AVCaptureSession AVCaptureDevice AVCaptureInput AVCaptureAudioDataOutput
AVAudioRecorder AVAudioPlayer AVAudioEngine AVAudioSession AVAudioRecorderDelegate
AVCaptureDeviceInput AVCaptureFileOutput AVFileType AVMediaType AVFoundationError
AVKit AVPlayer AVPlayerViewController AVPlayerItem AVPlayerLayer AVLooper AVQueuePlayer
AVAudioFormat AVSampleRateConverter
AVAudioApplication AVAudioFile AVAudioQuality AVAudioSessionInterruptionOptionKey
AVAudioSessionInterruptionTypeKey AVSpeechSynthesizer AVSpeechSynthesizerDelegate
AVSpeechUtterance AVSpeechBoundaryImmediate AVSpeechSynthesisVoice AVSpeechSynthesisVoiceGender
CMTime CMTimeRange CMTimeScale NSError NSKeyValueObservation NSRecursiveLock
MPNowPlayingInfoCenter MPRemoteCommandCenter MPChangePlaybackPositionCommandEvent
MPMediaItemPropertyPlaybackDuration MPMediaItemPropertyTitle MPMediaItemPropertyArtist
MPMediaItemPropertyAlbumTitle MPMediaItemPropertyPlaybackDuration MPNowPlayingInfoPropertyElapsedPlaybackTime
MPNowPlayingInfoPropertyPlaybackRate MPRemoteCommandHandlerStatus
Combine AnyCancellable Publisher AnyPublisher Just Future Deferred CurrentValueSubject
PassthroughSubject Subject ObservableObject Observable Published AppStorage SceneStorage
StateBinding StateObject ObservedObject EnvironmentObject Environment Bindable Binding
FocusState Namespace FocusScope AppStorage SceneStorage Transaction Transaction
ModelContext ModelContainer ModelEntity ModelConfiguration FetchDescriptor FetchRequest
Schema Macro Model PersistentModel IdentifiableType ModelActor ModelContext
SwiftData SwiftUI Combine Foundation CoreGraphics QuartzCore UIKit AVFoundation AVKit
CryptoKit SHA256 SHA512 HMAC Insecure
MediaPlayer UserNotifications
UNUserNotificationCenter UNAuthorizationStatus UNNotificationRequest UNNotificationContent
UNMutableNotificationContent UNTimeIntervalNotificationTrigger UNCalendarNotificationTrigger
UNNotificationAction UNNotificationCategory UNNotificationSound UNNotificationRequestOptions
UNAuthorizationOptions UNNotificationPresentationOptions
Observation Registrar Observable ObservationRegistrar ObservationAccess
Swift Standard Foundation Protocol Reflection Mirror
CGFloat CGPoint CGSize CGRect CGVector CGLineCap CGPath CGAffineTransform CGGradient
CGColor CGColorSpace CGContext CGBlendMode CGMutablePath CAGradientLayer CADisplayLink
CIFilter CIFilterContext NSRange NSAttributedString NSMutableAttributedString NSLayoutAnchor
NSLayoutDimension NSLayoutConstraint NSDirectionalEdgeInsets NSUserActivity
LocalizedError CustomNSError SwiftError StringEncoding Unicode ColorScheme Gesture
SIMD1 SIMD2 SIMD3 SIMD4 SIMD SIMD16
NSObjectProtocol NotificationCenter SIMD StrokeStyle SIMD2 SIMD4 UIActivityViewController
NSAttributedString UIUserInterfaceSizeClass UITextContentType
URLSession URLSessionTask URLSessionDataTask URLRequest URLResponse HTTPURLResponse URLCache
RunLoop Timer Operation OperationQueue DispatchQueue DispatchTime DispatchSemaphore
ProcessInfo Bundle FileManager JSONSerialization JSONDecoder JSONEncoder JSONSerialization.ReadingOptions
DateFormatter DateComponents DateIntervalFormatter NumberFormatter Locale Calendar TimeZone
ISO8601DateFormatter DateComponentsFormatter RelativeDateTimeFormatter
IndexPath IndexSet CharacterSet Scanner Notification UserDefaults Decimal NSDecimalNumber
Duration Instant Clock ContinuousClock SuspendedClock ClockProtocol Task TaskGroup AsyncStream
TaskPriority MainActor Actor GlobalActor Sendable CodableCodingUserInfoKey CodingUserInfoKey
Encoder Decoder KeyedEncodingContainer KeyedDecodingContainer SingleValueEncodingContainer
ButtonStyle ViewModifier EnvironmentKey Layout SubviewLayout Content Accessory Key
Context Configuration ProposedViewSize Subviews ToolbarContent ToolbarItem Placement
SectionedFetchRequest SortDescriptor Predicate FetchDescriptor Expression Attribute
Data Attribute PersistentModel AnySchema SchemaMigrationPlan ModelConfiguration
UUID URL Hashable Hasher AnyHashable Optional Array Dictionary Set
FailableInitializer Deinit Precedencegroup ForwardReference InfixOperator
AES Key SymmetricKey Curve25519 Signing P256 SigningKey
LanguageService
""".split())

KEYWORDS = set("""
let var func struct class enum actor protocol extension import return if else guard while
for in switch case default break continue defer do try catch throw throws rethrows as is
nil true false self Self super init deinit subscript typealias where some any inout
repeat when let static let open public internal private fileprivate package final indirect
lazy weak unowned mutating nonmutating override required convenience dynamic optional
associativity precedencegroup operator associativity left right none get set willSet didSet
async await actor isolated nonisolated distributed
""".split())


def strip_comments_and_strings(src: str) -> list[str]:
    """Blank out comments and string literals, preserving line structure."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        if ch == '"':
            # Multi-line string?
            if src.startswith('"""', i):
                i += 3
                while i < n and not src.startswith('"""', i):
                    if src[i] == "\\":
                        i += 2
                        continue
                    if src[i] == "\n":
                        out.append("\n")
                    i += 1
                i += 3
                out.append('""')
                continue
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 1
            out.append('""')
            continue
        out.append(ch)
        i += 1
    return "".join(out).split("\n")


def swift_files() -> list[tuple[str, str, str]]:
    """(module, path, relpath) for every source file we own."""
    files = []
    for module, base in MODULE_ROOTS:
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in (".build", "build", ".git")]
            for fn in sorted(filenames):
                if not fn.endswith(".swift"):
                    continue
                p = os.path.join(dirpath, fn)
                files.append((module, p, os.path.relpath(p, ROOT)))
    files.sort(key=lambda t: (t[0], t[2]))
    return files


def generic_params(line: str) -> set[str]:
    """Local generic parameter names declared in `func f<T, U>(...)` / `struct S<T>`."""
    names = set()
    for m in re.finditer(r"<\s*([A-Za-z_][A-Za-z0-9_, ]*)>", line):
        for part in m.group(1).split(","):
            part = part.strip().split(":")[0].strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", part or ""):
                names.add(part)
    return names


# --- type-position extraction -------------------------------------------------
# Contexts where an identifier is being used as a type. Deliberately noisy:
# false positives get filtered against declared types, KNOWN, and locals.

CONTEXTS = [
    # `-> Type` and `{ ... } -> Type`
    re.compile(r"->\s*(?:inout\s+)?(?:throws\s+)?([A-Za-z_][A-Za-z0-9_.]*)"),
    # `as? Type`, `as! Type`, `as Type`, `is Type`
    re.compile(r"\bas[?!]?\s+([A-Za-z_][A-Za-z0-9_.]*)"),
    re.compile(r"\bis\s+([A-Za-z_][A-Za-z0-9_.]*)"),
    # `some Type`, `any Type`
    re.compile(r"\b(?:some|any)\s+([A-Za-z_][A-Za-z0-9_.]*)"),
    # `Type.member(...)` — record the leading segment only when capitalised
    re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\."),
    # array/dictionary/optional sugar: `[Type]`, `Type?`, `Type!`, `Type.Type`
    re.compile(r"(?::|<|,\s*\[|\[\s*)\s*([A-Z][A-Za-z0-9_]*)\s*(?:\]|[?!,>)\s]|$)"),
    # `inout Type`, `borrowing Type`
    re.compile(r"\b(?:inout|borrowing|consuming)\s+([A-Za-z_][A-Za-z0-9_.]*)"),
    # type annotations on stored/computed properties and `let` bindings
    re.compile(r"\b(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*([A-Z][A-Za-z0-9_.]*)"),
    # function parameter / closure param / tuple element types
    re.compile(r"[,(]\s*[A-Za-z_][A-Za-z0-9_]*\s*(?:\.[A-Za-z_][A-Za-z0-9_]*\s*)*:\s*([A-Z][A-Za-z0-9_.]*)"),
    # `@Model final class X` style attributes carrying types, e.g. `@Relationship(deleteRule:)`
    re.compile(r"@State\b.*?\bof\s+([A-Z][A-Za-z0-9_.]*)"),
    re.compile(r"\bType\b\s*<"),
]

IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def collect_type_refs(lines: list[str]) -> list[tuple[str, str]]:
    """-> [(identifier, evidence-context)]"""
    found = []
    for raw in lines:
        for pat in CONTEXTS:
            for m in pat.finditer(raw):
                tok = m.group(1)
                if not tok:
                    continue
                # Take the base identifier of a dotted chain (Palette.brand -> Palette).
                base = tok.split(".")[0]
                if not re.match(r"^[A-Z][A-Za-z0-9_]*$", base):
                    continue
                found.append((base, tok))
    return found


def main() -> int:
    verbose = "-v" in sys.argv

    files = swift_files()
    decls: dict[str, list[tuple[str, str, int, str, bool]]] = defaultdict(list)
    top: dict[str, tuple[str, str, int, str]] = {}
    KIND_OF: dict[str, str] = {}
    inits: dict[str, list[tuple[str, str, int, str]]] = defaultdict(list)
    members: dict[str, set[str]] = defaultdict(set)
    static_members: dict[str, set[str]] = defaultdict(set)
    imports: dict[str, set[str]] = defaultdict(set)
    file_lines: dict[str, list[str]] = {}
    file_module: dict[str, str] = {}

    for module, path, rel in files:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
        lines = strip_comments_and_strings(raw)
        file_lines[rel] = lines
        file_module[rel] = module

        # Track lexical scope so a nested `Kind` in two different parents is not
        # mistaken for a redeclaration. Only depth-0 declarations collide.
        scope: list[str] = []
        depth = 0
        for idx, line in enumerate(lines, 1):
            m = DECL_RE.match(line)
            delta = line.count("{") - line.count("}")
            newdepth = depth + delta

            if m and m.group(1) in TYPE_KINDS:
                kind, name = m.group(1), m.group(2)
                top_level = not scope
                qualified = ".".join(scope + [name])
                decls[qualified].append((module, rel, idx, kind, top_level))
                if kind != "extension":
                    top[qualified] = (module, rel, idx, kind)
                KIND_OF[qualified] = kind
                if scope:
                    # `enum Curve` nested inside `extension Motion` makes
                    # `Motion.Curve` a valid reference; record it so the
                    # namespace-member check does not flag it.
                    members[scope[-1]].add(name)
                    static_members[scope[-1]].add(name)
                # An extension continues its own scope; it does not nest.
                if kind == "extension":
                    if scope:
                        scope[-1] = name
                    else:
                        scope.append(name)
                        depth = newdepth
                        continue
                else:
                    scope.append(name)
                depth = newdepth
                continue

            if scope:
                im = INIT_RE.search(line)
                if im:
                    inits[scope[-1]].append((rel, im.group(0).strip(), idx, ""))
                mm = MEMBER_RE.match(line)
                if mm:
                    members[scope[-1]].add(mm.group(2))
                    if mm.group(1):
                        static_members[scope[-1]].add(mm.group(2))

            im = EXPORT_RE.match(line) or IMPORT_RE.match(line)
            if im:
                imports[module].add(im.group(1).split(".")[0])

            depth = newdepth
            while scope and depth < len(scope):
                scope.pop()

    declared = set(decls)
    print("=" * 78)
    print("SWIFT SYMBOL INDEX  (heuristic — NOT a compiler)")
    print("=" * 78)
    print(f"files scanned      : {len(files)}")
    print(f"lines scanned      : {sum(len(v) for v in file_lines.values())}")
    print(f"distinct type names: {len(declared)}")
    print()

    # 1. redeclarations within the same module
    print("-" * 78)
    print("1. REDECLARATIONS (same module, same type name — cannot compile)")
    print("-" * 78)
    dupes = 0
    for name in sorted(decls):
        entries = decls[name]
        # Only module-level (top_level=True) declarations collide. A nested
        # `enum Kind` inside two unrelated parents is legal Swift.
        by_mod = defaultdict(list)
        for module, rel, idx, kind, tl in entries:
            if tl:
                by_mod[module].append((rel, idx, kind))
        if not by_mod:
            continue
        for module, lst in sorted(by_mod.items()):
            real = [e for e in lst if e[2] != "extension"]
            exts = [e for e in lst if e[2] == "extension"]
            if len(real) > 1:
                dupes += 1
                print(f"  !! {name} declared {len(real)}x in module {module}:")
                for rel, idx, kind in real:
                    print(f"       {rel}:{idx}  ({kind})")
            elif real and exts:
                print(f"     {name} [{module}] 1 decl + {len(exts)} extension(s):")
                for rel, idx, _ in real:
                    print(f"       decl  {rel}:{idx}")
                for rel, idx, _ in exts:
                    print(f"       ext   {rel}:{idx}")
    if dupes == 0:
        print("  (none)")
    print()

    # 2. imported modules
    print("-" * 78)
    print("2. IMPORTED MODULES")
    print("-" * 78)
    for module in sorted(imports):
        print(f"  {module}: {', '.join(sorted(imports[module]))}")
    print()

    # 3. unresolved type references
    print("-" * 78)
    print("3. UNRESOLVED TYPE REFERENCES")
    print("   (identifier used in type position, not declared here, not known, not local)")
    print("-" * 78)
    unresolved: dict[str, list[tuple[str, int, str]]] = defaultdict(list)
    # A `Type.member` reference where `member` is a declared capitalised member
    # is an enum case / static member, not an unresolved type.
    member_set: set[str] = set()
    for v in members.values():
        member_set |= v
    # Last segment of every qualified type name declared here (e.g. `IELTSLesson`
    # in `IELTSLesson.Kind`) counts as declared for reference resolution.
    declared_bases = set(declared)
    for q in declared:
        declared_bases.update(q.split("."))
    for rel, lines in file_lines.items():
        for raw in lines:
            locals_ = generic_params(raw)
            for base, tok in collect_type_refs([raw]):
                if base in declared_bases or base in KNOWN or base in KEYWORDS:
                    continue
                if base in locals_ or base in member_set:
                    continue
                if len(base) <= 2:
                    continue
                unresolved[base].append((rel, 0, tok))
    # dedupe per (name, rel, token)
    for name in sorted(unresolved):
        seen = set()
        rows = []
        for rel, _, tok in unresolved[name]:
            if (rel, tok) in seen:
                continue
            seen.add((rel, tok))
            lines = file_lines[rel]
            lineno = next(
                (i for i, l in enumerate(lines, 1) if re.search(r"\b%s\b" % re.escape(name), l)),
                0,
            )
            rows.append((rel, lineno, tok))
        print(f"  ?? {name}  ({len(rows)} site(s))")
        for rel, lineno, tok in rows[:6]:
            print(f"       {rel}:{lineno}")
        if len(rows) > 6:
            print(f"       ... +{len(rows) - 6} more")
    if not unresolved:
        print("  (none)")
    print()

    # 4. member access on our OWN namespaces (Radius.sm, Motion.reveal, ...)
    #    This is where most cross-lane drift lives: a lane assumed a design
    #    system member that the design-system lane never declared.
    print("-" * 78)
    print("4. MEMBER ACCESS ON LOCAL NAMESPACES (Radius./Spacing./Palette./Motion./...)")
    print("-" * 78)
    # A namespace is a type whose members are ALL static — Spacing, Radius,
    # Palette, Motion, Metric, Format. Types with instance members are not
    # token buckets and get skipped, otherwise every view would flag.
    member_of: dict[str, set[str]] = {}
    for tname in static_members:
        if "." in tname:
            continue
        st = static_members[tname]
        if len(st) < 2:
            continue
        if st >= members[tname]:
            member_of[tname] = st
    bad_member: dict[str, list[tuple[str, int, str]]] = defaultdict(list)
    for rel, lines in file_lines.items():
        for raw in lines:
            for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]*)\.([a-zA-Z_][A-Za-z0-9_]*)", raw):
                owner, mem = m.group(1), m.group(2)
                if owner not in member_of or owner in KNOWN:
                    # `KNOWN` owners are stdlib types we merely extend, so their
                    # other members are not ours to resolve.
                    continue
                if mem == "self" or mem in member_of[owner]:
                    continue
                if not re.fullmatch(r"[a-z][A-Za-z0-9_]*", mem):
                    continue
                bad_member[f"{owner}.{mem}"].append((rel, 0, ""))
    for key in sorted(bad_member):
        rows = sorted(set(bad_member[key]))
        # If some site of the member does resolve, it may be an extension in a
        # file we cannot see the body of; still worth reporting once.
        print(f"  !! {key}  — not a declared member of {key.split('.')[0]}")
        for rel, _, _ in rows[:5]:
            print(f"       {rel}")
        if len(rows) > 5:
            print(f"       ... +{len(rows) - 5} more site(s)")
    if not bad_member:
        print("  (none)")
    print()

    # 5. initialisers per type
    print("-" * 78)
    print("5. INITIALISERS DECLARED PER TYPE")
    print("-" * 78)
    for tname in sorted(inits):
        rows = sorted(set(inits[tname]), key=lambda r: (r[0], r[2]))
        print(f"  {tname}  ({len(rows)})")
        for rel, sig, lineno, _ in rows:
            print(f"       {rel}:{lineno}  {sig}")
    print()

    if verbose:
        print("-" * 78)
        print("6. ALL DECLARATIONS")
        print("-" * 78)
        for name in sorted(decls):
            for module, rel, idx, kind, tl in decls[name]:
                print(f"  {kind:10} {name:32} {module:13} {rel}:{idx}")

    print("=" * 78)
    print("A CLEAN RUN IS NOT PROOF OF COMPILATION. This script does not check")
    print("overload resolution, generic constraints, conformance, isolation,")
    print("access control, or any expression-level type checking.")
    print("=" * 78)
    return 1 if dupes else 0


if __name__ == "__main__":
    sys.exit(main())

# --- duplicate file basenames -------------------------------------------------
# Two Swift files with the same basename inside one target produce
# "Multiple commands produce '.../<Name>.stringsdata'". A type-declaration scan
# misses this when the two files declare *different* types, so check names too.
def duplicate_basenames(root="App"):
    import collections
    seen = collections.defaultdict(list)
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            if name.endswith(".swift"):
                seen[name].append(os.path.join(dirpath, name))
    dupes = {n: ps for n, ps in seen.items() if len(ps) > 1}
    if not dupes:
        print("duplicate file basenames: none")
        return 0
    print("duplicate file basenames: %d" % len(dupes))
    for name, paths in sorted(dupes.items()):
        print("  ERROR %s -> %s" % (name, ", ".join(sorted(paths))))
    return len(dupes)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--basenames":
        raise SystemExit(1 if duplicate_basenames() else 0)
