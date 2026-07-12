# UniLink Control Handoff - 2026-07-11

## Current Status

The workspace is intentionally dirty. Preserve all existing user and prior-agent changes; do not reset, clean, or revert unrelated files.

### Public Remote-Control Investigation

- The Windows Quick Support target `24 162 334` was discovered through `rs-ny.rustdesk.com:21116`.
- Controller logs show direct TCP punch attempts followed by Windows error `10054` (the remote host forcibly closed the existing connection).
- A per-peer relay preference was corrected into the peer `[options]` section, but the user still received `10054`.
- This is an unresolved foundation issue. Do not claim Quick Support or public relay is verified until a password prompt and real desktop session both succeed.

### Unified Device Connection Entry

Implemented a shared connection-decision dialog:

- `flutter/lib/hanako/connection_decision.dart`
- `flutter/lib/hanako/device_list_panel.dart`
- `flutter/lib/hanako/top_device_dropdown.dart`

The primary action is remote control. The dialog probes and presents SSH and SMB drive availability on the local network, while retaining public-server connection as a secondary choice.

### Mac Window Mode

Implemented and built:

- Local crop via `CanvasModel.remoteViewRect`.
- Existing input mapping sends cropped-view pointer coordinates back as full Mac desktop coordinates.
- New display projection chooses the display owning the target Mac window, including overlap fallback for windows straddling displays.
- Independent Mac window sessions now open on the selected display instead of always display `0`.
- Removed the normal open path's dependency on the global server crop file, because it can affect the parent full-desktop session. Local crop keeps the normal desktop view intact.

Files:

- `flutter/lib/hanako/mac_window_mode.dart`
- `flutter/lib/desktop/pages/remote_page.dart`
- `flutter/lib/common/widgets/toolbar.dart`
- `flutter/test/mac_window_projection_test.dart`

## Verification Completed

```powershell
cd D:\agents\codex\hanako-control\client\rustdesk\flutter
D:\tools\flutter\bin\flutter.bat test test/mac_window_projection_test.dart
D:\tools\flutter\bin\flutter.bat build windows --release
```

Results on 2026-07-11:

- Mac window projection tests: passed (2 tests).
- Windows Flutter Release build: passed.

## Still Required Before Marking Complete

1. Real Mac test with normal DPI, Retina/mixed DPI, and a second display.
2. Verify crop framing, click, drag, wheel, keyboard, resize, refresh, and close return path.
3. Re-run the full basic remote-control regression when a working public or LAN target is available.
4. Continue the master checklist with file/clipboard reliability, then unified LAN/native-service paths.

## Additional Work Completed After This Handoff

- Android LAN connection now supports Windows RDP and Mac VNC handoff.
- Desktop connection decision probes reachable RDP/VNC services and launches the installed system client.
- Finder selection download skips symbolic links and rejects zero-file completion.
- Windows Release and Android Debug builds both passed after these changes.
- `scripts/generate_unilink_update_manifest.ps1` and `scripts/publish_unilink_release.ps1` already provide the repeatable manifest/release flow; `latest.json` contains non-empty platform hashes.

### Real Test Result, 2026-07-12

- Windows -> Mac native VNC handoff passed: UniLink probed `192.168.137.2:5900`, found the installed TigerVNC viewer, launched it with the resolved target, and the user reached the Mac desktop.
