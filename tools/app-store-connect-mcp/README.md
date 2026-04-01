# App Store Connect MCP (local pin)

This folder pins [appstore-connect-mcp-server](https://www.npmjs.com/package/appstore-connect-mcp-server) (upstream repo was archived on GitHub; the npm package remains usable).

## Install / update

```bash
cd tools/app-store-connect-mcp && npm install
```

## Run (stdio MCP)

```bash
npm run mcp
```

Requires env vars (same as Apple’s API key auth):

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_P8_PATH` — absolute path to the `.p8` file

Optional: `APP_STORE_CONNECT_VENDOR_NUMBER` (sales/finance report tools).

## Cursor

Copy `../../.cursor/mcp.json.example` → `../../.cursor/mcp.json` and fill in paths. Restart Cursor after editing.
