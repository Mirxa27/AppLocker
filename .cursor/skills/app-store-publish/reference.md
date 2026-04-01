# App Store Connect MCP — env and tools

## Environment variables (stdio server)

| Variable | Required | Purpose |
|----------|----------|---------|
| `APP_STORE_CONNECT_KEY_ID` | Yes | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Yes | Issuer UUID |
| `APP_STORE_CONNECT_P8_PATH` | Yes | Absolute path to `.p8` private key |
| `APP_STORE_CONNECT_VENDOR_NUMBER` | No | Sales / finance report tools |

## Repo script env (binary upload)

See `scripts/publish-appstore.sh` and `RELEASE.md`: `ASC_API_*`, `UPLOAD_TO_APP_STORE_CONNECT`, optional `APPLE_ID` + `APPLE_ASC_PASSWORD`.

## Typical MCP tools (package v1.1.x)

Names may vary slightly by version; ask the MCP server for its tool list if unsure.

- Apps: `list_apps`, `get_app_info`
- Versions & localizations: `list_app_store_versions`, `create_app_store_version`, `list_app_store_version_localizations`, `get_app_store_version_localization`, `update_app_store_version_localization`
- Beta: `list_beta_groups`, `list_group_testers`, `add_tester_to_group`, `remove_tester_from_group`
- Bundle IDs / devices / users / analytics: as listed in upstream README

## Upstream

- Archived source: [github.com/JoshuaRileyDev/app-store-connect-mcp-server](https://github.com/JoshuaRileyDev/app-store-connect-mcp-server)
- NPM: `appstore-connect-mcp-server`
