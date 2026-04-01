.PHONY: all generate-project build build-macos build-ios release release-signed publish-appstore clean test install help

all: build

generate-project:
	xcodegen generate --spec /Users/abdullahmirxa/Documents/GitHub/AppLocker/project.yml

build: build-macos

build-macos: generate-project
	xcodebuild -project /Users/abdullahmirxa/Documents/GitHub/AppLocker/AppLocker.xcodeproj -scheme AppLocker -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build

build-ios: generate-project
	xcodebuild -project /Users/abdullahmirxa/Documents/GitHub/AppLocker/AppLocker.xcodeproj -scheme AppLockerCompanion -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build

test:
	swift test --package-path /Users/abdullahmirxa/Documents/GitHub/AppLocker

release: generate-project
	@/Users/abdullahmirxa/Documents/GitHub/AppLocker/scripts/build-release.sh

release-signed: generate-project
	@/Users/abdullahmirxa/Documents/GitHub/AppLocker/scripts/release-signed.sh

publish-appstore: generate-project
	@/Users/abdullahmirxa/Documents/GitHub/AppLocker/scripts/publish-appstore.sh

install: release
	cp -R /Users/abdullahmirxa/Documents/GitHub/AppLocker/release/AppLocker.app /Applications/

clean:
	swift package clean --package-path /Users/abdullahmirxa/Documents/GitHub/AppLocker
	rm -rf /Users/abdullahmirxa/Documents/GitHub/AppLocker/release

help:
	@echo "AppLocker Makefile commands:"
	@echo "  make generate-project  Regenerate the Xcode project from project.yml"
	@echo "  make build-macos       Build the macOS app with Xcode"
	@echo "  make build-ios         Build the iOS companion for iOS Simulator"
	@echo "  make test              Run SwiftPM unit tests"
	@echo "  make release           Archive and package an unsigned local macOS release"
	@echo "  make release-signed    Archive, sign, and optionally notarize a macOS release"
	@echo "  make publish-appstore  Archive and export iOS + macOS App Store artifacts"
	@echo "  make install           Copy the packaged app into /Applications"
	@echo "  make clean             Remove package and release artifacts"
