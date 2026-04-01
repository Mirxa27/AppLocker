---
name: app-store-publish
description: >-
  Publishes AppLocker (and similar Apple apps) via repo scripts plus App Store Connect MCP:
  verify entitlements, sync icons, bump versions, archive/export/upload, then ASC metadata
  and versions through MCP tools. Use when the user wants App Store Connect publishing,
  resubmission after rejection, TestFlight, or updating “What’s New” / localizations.
---

# App Store publish (AppLocker)

## Prerequisites

1. **Apple Developer**: Team ID in `project.yml` (`DEVELOPMENT_TEAM`), valid signing for App Store distribution.
2. **API key**: App Store Connect API key (`.p8`), Key ID, Issuer ID — same as `ASC_API_*` / `APP_STORE_CONNECT_*` env vars.
3. **Local tools**: Xcode, `xcodegen`, Node.js (for MCP).

## One-time: App Store Connect MCP in Cursor

Upstream project [JoshuaRileyDev/app-store-connect-mcp-server](https://github.com/JoshuaRileyDev/app-store-connect-mcp-server) is **archived** on GitHub; the **npm package** `appstore-connect-mcp-server` remains usable. This repo pins it under `tools/app-store-connect-mcp/`.

1. `cd tools/app-store-connect-mcp && npm install`
2. Copy `.cursor/mcp.json.example` → `.cursor/mcp.json` (gitignored).
3. Set **absolute** `APP_STORE_CONNECT_P8_PATH` and Key ID / Issuer ID in `mcp.json` `env`.
4. Restart Cursor. If `${workspaceFolder}` is not expanded by your Cursor version, replace the `node` `args` path with the full path to `node_modules/appstore-connect-mcp-server/dist/src/index.js`.

## Repo-local checks (before any archive)

Run in order:

1. `make verify-entitlements` — fails if `SupportingFiles/*/*.entitlements` are empty/corrupt (common cause of review failures).
2. `swift test` or `make test`.
3. **Icons**: Master is `Sources/AppLocker/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`. Regenerate all slots with `./scripts/sync-app-icons-from-1024.sh` after changing the master.
4. **Version**: Edit `project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, then `xcodegen generate --spec project.yml`.

## Build & upload binaries (CLI)

- Full App Store export + optional upload: `make publish-appstore` (see `RELEASE.md`).
- Upload env vars match `scripts/publish-appstore.sh`: either `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`, or `APPLE_ID` + `APPLE_ASC_PASSWORD` for `altool`.
- macOS `.pkg` needs installer signing identity when exporting macOS; iOS needs valid provisioning.

## MCP-assisted ASC tasks (after build is in App Store Connect)

Use the MCP server tools for metadata and versions (examples — exact tool names match the installed package):

- **Discovery**: `list_apps`, `get_app_info` (filter by bundle ID, e.g. `com.mirxa.AppLocker`).
- **Versions**: `list_app_store_versions`, `create_app_store_version` (platform `MAC_OS` / `IOS`), attach build when ready.
- **Store listing**: `list_app_store_version_localizations`, `update_app_store_version_localization` for `description`, `keywords`, `whatsNew`, URLs.
- **Beta**: `list_beta_groups`, `list_group_testers`, etc.

Always confirm **platform** (iOS vs macOS) and **app record IDs** from `get_app_info` before updating.

## Resubmission checklist (2.1.x / 2.3.x / 2.4.x)

- Entitlements verified; screenshots match current UI; review notes explain Accessibility / passcode flows.
- See `RELEASE.md` section **App Store Connect — macOS resubmission**.

## Additional detail

- MCP env var names and tool inventory: [reference.md](reference.md)
- Pinned MCP package README: [tools/app-store-connect-mcp/README.md](../../tools/app-store-connect-mcp/README.md)
