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

## validate-content: run the full content validator (schema, answers, cross-references)
.PHONY: validate-content
validate-content:
	@python3 Scripts/validate_content.py

## lint-content: alias of validate-content
.PHONY: lint-content
lint-content: validate-content

## archive-unsigned: archive the app with no code signature, no IPA packaging
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
