# UniLink Control Handoff - 2026-07-16

## Priority

The active stage is foundation reliability. The 1.4.14 release is blocked on Windows installation consistency, LAN/public routing isolation, UniLink black-screen recovery, and TigerVNC black-screen verification. See `docs/UNILINK_RELEASE_CHECKLIST_1.4.14.md`.

## Windows Runtime State

- Program Files 1.4.12+70 GUI, tray, and service are currently running.
- The AppData 1.4.11 installation and stale user shortcuts still exist; do not delete them until controlled migration and backup are implemented.
- Automatic update remains disabled pending a clean single-install update test.
- The user explicitly deferred the mixed-install cleanup to 1.4.14.

## LAN Routing Finding

- `192.168.137.2:21118` was reachable from Windows.
- The peer config had `force-always-relay = 'Y'`; it was backed up and changed to `N`.
- The global config had `allow-websocket = 'Y'`. A temporary change to `N` was restored to `Y` by the running application's official-line policy after restart, so editing TOML is not a durable repair.
- Source now treats literal IPv4/IPv6 peer IDs as direct targets and prevents implicit force-relay, WebSocket, or proxy state from overriding them. Focused Rust tests passed: 2 passed, 0 failed.
- The source fix has not been packaged, installed, or physically verified. Do not claim the live 1.4.12 client is repaired by this source-only change.
- Windows 1.4.14 Release was built on 2026-07-16 after `flutter pub get --offline` recovered from an online dependency handshake failure. The installer is `rustdesk-1.4.14-install.exe`; its product/file version is `1.4.14`, installer SHA-256 is `56456BAB87C24CB8ED091F7D9BB0420AE0CD9E31ACF48335BDB5FD7521A701AB`, and the packaged/core DLL SHA-256 is `269199F96CCECA62AE1CDAA3045921983E8BE54CEE644D4A3E7081C8C245DA74`.
- The 1.4.14 installer has not been installed over the current 1.4.12 Program Files plus 1.4.11 AppData mixed state. Do not use this build as evidence that migration, automatic update, or basic remote-control regression is complete.

## Black-Screen State

- TigerVNC 1.16.0 is installed and the Mac VNC endpoint was reachable earlier, but the current black-screen report has not been reproduced to a confirmed root cause.
- UniLink client logs show sessions to `192.168.137.2` starting and then exiting quickly, including `Reset by the peer` in some attempts.
- Computer Use was stopped by the user with Escape before a final visual connection test. Do not resume UI automation without a new user request.

## Verification Evidence

- `cargo test --lib direct_peer_id_tests --features hwcodec,vram,flutter`: 2 passed.
- The successful test required Visual Studio `vcvars64.bat` and ASCII `CARGO_HOME=D:\agents\codex\.cargo-unilink` because NASM cannot reliably build dependencies from the non-ASCII user profile path.
- Existing unrelated Rust warnings remain; do not widen this task to clean them.

## Current 1.4.14 Verification Boundary

- Windows build-level verification is complete: Rust Release, Flutter Windows Release, portable packaging, product version, and DLL hash matching passed.
- Mac is not nearby, so Mac UniLink, TigerVNC, black-screen recovery, permissions, window mode, and cross-platform connection tests are explicitly deferred.
- No GitHub Release or `latest.json` update was made for 1.4.14. The existing remote manifest remains 1.4.11 until the P0 installation, routing, black-screen, and regression gates are closed.

## Cross-Version Connection Finding

- On 2026-07-16, Android 1.4.12 showed `Failed to connect to rs-ny.rustdesk.com:21116` while connecting to the Windows 1.4.14 target. This is failure to reach the public rendezvous server before device lookup; it is not evidence of a 1.4.12/1.4.14 protocol incompatibility.
- The Windows 1.4.14 config uses `rs-ny.rustdesk.com:21116` and has `allow-websocket = 'Y'`. Windows TCP reachability to 21116 succeeded, and an explicit WebSocket upgrade to `https://rs-ny.rustdesk.com/ws/id` returned `101 Switching Protocols`.
- The immediate mobile recovery path is to restore the official server line and enable `Use WebSocket` on the Android client, then force-close and reopen it. Same-LAN direct connection is the fallback when the phone network cannot reach the public line.
- ADB was not connected during this check, so the Android network path was not physically tested from the phone.

## Workspace Safety

The main worktree remains intentionally dirty with unrelated release, UI, Android, connection, and service work. Never reset, clean, broadly stage, or delete unknown changes.
