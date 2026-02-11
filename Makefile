# AppLocker Makefile
# Quick commands for building and releasing

.PHONY: all build release clean test install

# Default target
all: build

# Build debug version
build:
	swift build

# Build release version
release:
	@./scripts/build-release.sh

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build/release
	rm -rf release/

# Run tests
test:
	swift test

# Install locally (copy to /Applications)
install: release
	@echo "Installing to /Applications..."
	@cp -R release/AppLocker.app /Applications/
	@echo "✅ Installed to /Applications/AppLocker.app"

# Create a new version tag and release
# Usage: make version VERSION=3.1
version:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make version VERSION=3.1"; \
		exit 1; \
	fi
	@echo "Creating version $(VERSION)..."
	@# Update Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" AppLocker.app/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" AppLocker.app/Contents/Info.plist
	@echo "Updated version to $(VERSION)"
	@echo "Next steps:"
	@echo "  1. Commit changes: git add -A && git commit -m 'Bump version to $(VERSION)'"
	@echo "  2. Create tag: git tag -a v$(VERSION) -m 'Release v$(VERSION)'"
	@echo "  3. Push: git push origin main && git push origin v$(VERSION)"

# Quick run for development
run: build
	@echo "Running AppLocker..."
	@./AppLocker.app/Contents/MacOS/AppLocker &

# Show help
help:
	@echo "AppLocker Makefile Commands:"
	@echo ""
	@echo "  make build      - Build debug version"
	@echo "  make release    - Build and package release version"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make test       - Run tests"
	@echo "  make install    - Install to /Applications"
	@echo "  make version    - Create new version (e.g., make version VERSION=3.1)"
	@echo "  make run        - Build and run for development"
	@echo "  make help       - Show this help"
