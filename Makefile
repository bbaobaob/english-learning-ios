SHELL := /bin/bash
.DEFAULT_GOAL := help
.ONESHELL:
SHELLFLAGS := -eu -o pipefail -c
CONTENT_DIR := Packages/EnglishCore/Resources/content
PROJECT := EnglishLearning.xcodeproj

## help: list available targets
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /' | sort

## project: generate the .xcodeproj from project.yml (requires xcodegen)
.PHONY: project
project:
	command -v xcodegen >/dev/null || { echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2; exit 1; }
	xcodegen generate

## build: generate the project and build the app for the simulator
.PHONY: build
build: project
	xcodebuild -project $(PROJECT) -scheme EnglishLearning \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

## test: run the full test suite (both packages)
.PHONY: test
test: test-core test-store

## test-core: swift test on EnglishCore (portable, also runs on Linux CI)
.PHONY: test-core
test-core:
	swift test --package-path Packages/EnglishCore

## test-store: swift test on EnglishStore (SwiftData, requires macOS 14+)
.PHONY: test-store
test-store:
	swift test --package-path Packages/EnglishStore

## validate-content: parse every content JSON and check the 19 topics resolve
.PHONY: validate-content
validate-content:
	@printf '%s\n' \
	  'import json, os, sys' \
	  '' \
	  'ROOT = "Packages/EnglishCore/Resources/content"' \
	  'TOPICS = os.path.join(ROOT, "topics")' \
	  'EXPECTED = 19' \
	  'errors = []' \
	  '' \
	  'if not os.path.isdir(ROOT):' \
	  '    sys.exit("content root not found: %s" % ROOT)' \
	  '' \
	  'files = sorted(' \
	  '    os.path.join(d, n)' \
	  '    for d, _sub, names in os.walk(ROOT) for n in names if n.endswith(".json")' \
	  ')' \
	  'if not files:' \
	  '    sys.exit("no .json files under %s" % ROOT)' \
	  '' \
	  'for path in files:' \
	  '    raw = open(path, encoding="utf-8").read()' \
	  '    if not raw.strip():' \
	  '        errors.append("%s: empty file" % path)' \
	  '        continue' \
	  '    try:' \
	  '        json.loads(raw)' \
	  '    except ValueError as exc:' \
	  '        errors.append("%s: invalid JSON: %s" % (path, exc))' \
	  '' \
	  'index_path = os.path.join(ROOT, "content.json")' \
	  'ids = []' \
	  'if not os.path.isfile(index_path):' \
	  '    errors.append("content.json: missing index file")' \
	  'else:' \
	  '    index = json.load(open(index_path, encoding="utf-8"))' \
	  '    for entry in index.get("topics", index.get("topicIDs", [])):' \
	  '        ids.append(entry["id"] if isinstance(entry, dict) else entry)' \
	  '    if len(ids) != EXPECTED:' \
	  '        errors.append("content.json: expected %d topic ids, found %d" % (EXPECTED, len(ids)))' \
	  '    if len(set(ids)) != len(ids):' \
	  '        errors.append("content.json: duplicate topic ids")' \
	  '' \
	  'if not os.path.isdir(TOPICS):' \
	  '    errors.append("topics/: directory not found")' \
	  'else:' \
	  '    for topic_id in ids:' \
	  '        if not os.path.isfile(os.path.join(TOPICS, topic_id + ".json")):' \
	  '            errors.append("topics/%s.json: listed in content.json but missing" % topic_id)' \
	  '' \
	  'if errors:' \
	  '    for err in errors:' \
	  '        print("ERROR: " + err, file=sys.stderr)' \
	  '    sys.exit("%d content error(s)" % len(errors))' \
	  'print("content ok: %d json files, %d topics" % (len(files), len(ids)))' \
	  | python3 -

## lint-content: alias of validate-content
.PHONY: lint-content
lint-content: validate-content

## archive-unsigned: archive the app with signing disabled, no IPA packaging
.PHONY: archive-unsigned
archive-unsigned: project
	xcodebuild -project $(PROJECT) -scheme EnglishLearning -configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath build/EnglishLearning.xcarchive -derivedDataPath .build \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" SKIP_INSTALL=NO archive

## sim: list booted simulators
.PHONY: sim
sim:
	xcrun simctl list devices | grep -i booted || echo "no booted simulator: xcrun simctl boot 'iPhone 16'"

## clean: remove all generated build products
.PHONY: clean
clean:
	rm -rf .build build DerivedData $(PROJECT) App/Info.plist
