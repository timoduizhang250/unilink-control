# UniLink Control Server Lines

Updated: 2026-07-09

## Product Decision

UniLink now exposes "server lines" in settings. The goal is to let a non-technical user switch the RustDesk discovery/relay backend without editing TOML files or running admin scripts.

Both devices must use the same line:

- Windows/macOS: Settings -> Network -> Server lines.
- Android/Harmony: Settings -> ID/Relay Server -> Server lines.

## Built-In Lines

### Official Public

- ID server: empty
- Relay server: empty
- API server: empty
- Key: empty
- Use: first-party/default public RustDesk line.
- Risk: mobile access can be restricted by region; this was observed in UniLink testing.

### HITOHA Free

- ID server: `103.131.188.71`
- Relay server: `103.131.188.71`
- API server: empty
- Key: `xMnueFSYC65LbBsCOGJKj29N0fU8ZEPJ0NqZZiARbW0=`
- Use: free Singapore RustDesk relay line, suitable for testing when the official public line rejects mobile.
- Risk: third-party free service, so speed, uptime, and privacy guarantees are not controlled by UniLink.

Do not set HITOHA API to `https://103.131.188.71` in UniLink by default. The certificate was observed to mismatch the IP address. API only affects account/device-list features, not manual ID remote control.

## Implementation

- Shared line definitions: `flutter/lib/hanako/public_server.dart`
- Windows/macOS UniLink settings card: `flutter/lib/desktop/pages/desktop_setting_page.dart`
- Android/Harmony server settings dialog: `flutter/lib/mobile/widgets/dialog.dart`

Applying a built-in line writes these RustDesk options through the normal Flutter/Rust bridge:

- `custom-rendezvous-server`
- `relay-server`
- `api-server`
- `key`
- `direct-server = N`
- `allow-websocket = Y`
- `local-ip-addr = ''`

Do not write `UniLink Control2.toml` directly for this. The service can sync over direct file edits.

## Adding Another Free Line

Only add a public line if it has an official/public source that clearly publishes:

- ID server
- Relay server
- Key
- Whether API server is required

If any of those are missing, leave it for "Manual custom" instead of shipping it as built-in.
