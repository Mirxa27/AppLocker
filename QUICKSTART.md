# Quick Start - Building & Releasing

## 🚀 Quick Commands

```bash
# Build for development
make build

# Build release version (creates DMG)
make release

# Install to /Applications
make install

# Create new version
make version VERSION=3.1
```

## 📦 Creating a Release

### Option 1: Automated (GitHub Actions) - RECOMMENDED

```bash
# 1. Commit your changes
git add -A
git commit -m "Release v3.1"
git push origin main

# 2. Create and push tag (version derived from tag)
git tag -a v3.1 -m "Release v3.1"
git push origin v3.1
```

GitHub Actions will automatically:

- ✅ Build the app
- ✅ Create DMG installer
- ✅ Create GitHub Release
- ✅ Attach DMG to release

### Option 2: Manual Build

```bash
# Build locally
make release

# Find artifacts in release/
ls release/
# AppLocker.app
# AppLocker-3.0.dmg
```

## 🔧 Development

```bash
# Build and run
make run

# Clean build artifacts
make clean

# Run tests
make test
```

## 📋 Files Added

- **Makefile** - Quick commands
- **scripts/build-release.sh** - Build script
- **.github/workflows/build.yml** - CI/CD automation
- **RELEASE.md** - Detailed release guide
- **CHANGELOG.md** - Version history

## 🏷️ Version Format

We use Semantic Versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes

Example: `3.1.0`

## ✨ What Gets Created

When you run `make release`:

1. **release/AppLocker.app** - Signed app bundle (~1.8 MB)
2. **release/AppLocker-X.X.dmg** - DMG installer (~5 MB)

## 🌐 GitHub Repository

**URL**: https://github.com/Mirxa27/AppLocker

**Latest Release**: Check the "Releases" tab on GitHub

## 🆘 Troubleshooting

### Build fails

```bash
make clean
make release
```

### Signing issues

```bash
codesign --remove-signature AppLocker.app
codesign --force --deep --sign - AppLocker.app
```

### DMG won't mount

```bash
# Recreate manually
hdiutil create -volname "AppLocker" -srcfolder AppLocker.app -ov -format UDZO AppLocker.dmg
```

## 📚 More Info

- Full release guide: [RELEASE.md](RELEASE.md)
- Version history: [CHANGELOG.md](CHANGELOG.md)
- CI/CD config: [.github/workflows/build.yml](.github/workflows/build.yml)
