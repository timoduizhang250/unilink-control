# UniLink Control Master Execution Checklist

Updated: 2026-07-17
Status legend:

- [x] Verified: implemented and verified at the stated level.
- [~] Implemented / partial: code or a flow exists, but needs the listed validation or is intentionally incomplete.
- [ ] Not started.

This is the active total checklist. The filename is retained to preserve existing links.

## North Star

UniLink makes Windows, macOS, and Android feel like one connected personal work environment. Remote control and LAN connectivity are foundations for seamless continuation, not the product identity by themselves.

## A. Product Foundation and Reliability

- [~] Windows desktop UniLink `1.4.15+73` builds and is installed from Program Files; current end-to-end remote-control regression still needs a fresh test.
- [~] Windows now runs the Program Files `1.4.15+73` GUI/tray/service. The old AppData `1.4.11+69` executable was recoverably renamed to `.disabled-*`, launch paths point to Program Files, and configuration hashes were preserved; reboot and uninstall recovery remain unverified.
- [~] Android UniLink debug APK builds and installs; latest LAN-RDP build has been generated but not installed on the currently disconnected ADB device.
- [~] Windows/Mac/Android device and session UI exists; all visible actions still need a systematic functional audit.
- [~] Android 1.4.11 -> Windows 1.4.11 over the official public server reached the live Windows desktop on 2026-07-15. The user confirmed the session connected and declined further input regression; pointer, drag, keyboard, disconnect, and reconnect remain unverified.
- [~] The same Android -> Windows session used a distant relay because Android Wi-Fi was disabled (cellular `10.91.*`) while Windows was on Wi-Fi (`192.168.1.*`). Measured Windows-to-relay RTT was about 330 ms and Android-to-relay RTT about 347 ms, so low-latency public control is not accepted yet; same-LAN direct routing and honest relay diagnostics remain required.
- [x] Android official-server WebSocket handling was changed to use secure WebSocket for RustDesk domains; focused Rust test passed.
- [~] Built-in official-line switching now restores WebSocket mode, waits for reconnect, and rolls back server/account state on failure. HITOHA remains visible but disabled because its registration protocol and packet loss failed real-device testing. Focused Flutter policy tests passed; Windows/Android real-device switching still needs the 1.4.12 build.
- [~] Desktop account login/logout is exposed in UniLink settings, and the primary desktop/mobile/My Devices connection entries require a controller login only for the official public line. LAN addresses, custom servers, and the unlogged-in target role remain available. Policy tests passed; real official login and reconnect need 1.4.12 device verification.
- [~] Remote sessions now report device-direct versus public-relay routing and show one high-latency hint at 250 ms or above. Parsing and threshold tests passed; visual timing still needs a real 1.4.12 session.
- [~] One-time password and online-status behavior have been improved during testing, but need regression testing across reconnects and network changes.
- [~] Windows -> Mac LAN direct control on macOS 15.2 reached a live 1680x1050 desktop after the 1.4.12 bundle received Screen Recording and Accessibility approval. A duplicate user-server restart loop was cleared and one stable `--server` listener remained; pointer, drag, keyboard, disconnect, and reconnect still need explicit regression.
- [ ] Full basic regression: Windows-to-Windows, Windows-to-Mac, Android-to-Windows, Android-to-Mac, including screen, pointer, drag, keyboard, disconnect, and reconnect.

Acceptance: every supported basic path has a real device test record, not just a successful connection dialog.

## B. Unified My Devices and Connection Decision

- [~] "My Devices" and device list UI exist on desktop; Android device list experience is partially present.
- [ ] Normalize device states: online, offline, connecting, permission required, client update required, and unavailable.
- [ ] One user action chooses the best available connection: existing UniLink session, LAN direct path, or explicitly configured native system service.
- [ ] Keep manual details such as IP, port, username, or server line behind an advanced/repair path.
- [ ] Keep connection history meaningful and accessible without crowding the home page.
- [ ] Audit every front-end action and remove or connect any button that has no real behavior.

Acceptance: a user can select their device and understand the next action without knowing a protocol name.

## C. Cross-Device Continuity

- [~] Windows-to-Mac file upload via SSH/SFTP is implemented with Finder-location preference and Downloads fallback; needs current real-device regression.
- [~] Mac-to-Windows selected-file download and Windows native drag-out are implemented. Download now rejects non-downloadable selections and does not follow remote symbolic links; true unconstrained Finder drag extraction is not implemented.
- [~] SSH terminal and Windows SMB mount helpers are implemented; need current credential/network regression.
- [ ] Cross-device clipboard reliability and conflict behavior.
- [ ] Present file movement as a simple continuation workflow, with clear fallback feedback instead of protocol jargon.
- [ ] Define and implement recent files / handoff workflow only after the transfer basics are stable.

Acceptance: common file and terminal workflows continue across Windows and Mac without losing the user's place.

## D. Mac Window Mode: Short-Term Working Version

- [x] Enumerate visible Mac windows and activate a selected window.
- [x] Open a separate UniLink remote window carrying target window metadata.
- [~] Crop the remote image to the selected Mac window bounds. Implemented with local crop; Windows Release build passed. Real Mac validation remains.
- [~] Map pointer click, drag, scroll, and keyboard input from the cropped local window back to the Mac display coordinates. Existing `remoteViewRect` input mapping is used; real Mac validation remains.
- [~] Handle DPI, scaling, and multi-display coordinates correctly. Added display projection and multi-display geometry tests; real mixed-DPI Mac validation remains.
- [ ] Ensure opening/closing a window-mode view does not interrupt normal remote control.
- [ ] Real-device verify normal, zoomed, and multi-display cases.

Acceptance: a pulled-out Mac window can be seen and operated accurately, with normal full-desktop remote control still intact.

## E. Mac Window Mode: Mid-Term Seamless Experience

- [ ] Make remote Mac windows feel native in position, title, size, focus, and lifecycle.
- [ ] Support multiple independently controlled remote Mac windows without input crossing between them.
- [ ] Synchronize close/minimize/hidden-state feedback.
- [ ] Provide reliable return to full desktop and fallback on any window-mode failure.
- [ ] Research and decide on ScreenCaptureKit single-window capture after the crop-and-map path is stable.

Acceptance: a user can work with remote Mac application windows as if they had been brought onto the local desktop.

## F. LAN and Native-Service Foundation

- [~] Android can hand off a Windows LAN target to an installed RDP client using IP, username, and port; build passed, real-device handoff remains unverified.
- [~] A Windows Home compatible UniLink Quick Support package can be built for a target that does not have UniLink installed; the 2026-07-11 package build and branding metadata were verified, but a real target-to-controller session still needs testing.
- [~] Android now uses one LAN connection entry for Windows RDP and Mac VNC handoff. Android device/client handoff needs physical-device verification.
- [x] Windows controller: probe and launch reachable macOS Screen Sharing/VNC sessions using installed/system clients. Verified 2026-07-12 with TigerVNC to `192.168.137.2:5900`. Windows RDP still needs its own real-device test.
- [~] macOS controller: the same reachable RDP/VNC URI launcher is implemented; a macOS build and real client handoff remain.
- [~] Android controller can hand off Mac VNC; Android UniLink LAN-direct session needs physical-device verification.
- [ ] Android target: improve UniLink LAN discovery, permissions, status, and stable direct session verification.
- [ ] Persist connection profiles safely; never store passwords in plain text without an approved secure-storage design.
- [ ] Keep native-service handoffs clearly distinct from embedded UniLink sessions.

Acceptance: all three UniLink platforms can initiate legitimate local-network connections to supported targets, with accurate setup and failure guidance.

## G. Settings and Product UI

- [~] A new glass-like Chinese UI direction and settings redesign exists in parts of the desktop app; functional parity audit remains.
- [ ] Ensure settings window size/layout is consistent with the home surface and no content overflows.
- [ ] Remove obsolete device shortcut/history placements only after relocating needed workflows.
- [ ] Make every setting a real persisted toggle, real action, or honest status row.
- [ ] Use Penpot design as reference only after its layout maps to real workflows and current components.
- [ ] Do not start first-run onboarding until core connection and continuity flows are stable.

Acceptance: the UI is coherent, Chinese-readable, responsive, and every control is functional.

## H. Release, Updates, and Trust

The active coordinated release plan is `docs/UNILINK_RELEASE_CHECKLIST_1.4.15.md`. It supersedes 1.4.14 as the next three-platform release plan. The existing `docs/UNILINK_RELEASE_CHECKLIST_1.4.14.md` remains historical evidence for the Windows field build.

- [x] UniLink Control 1.4.11 GitHub Release is published to `timoduizhang250/unilink-control-releases` with Windows x86_64 EXE, macOS x86_64 DMG, Android arm64 APK, and `latest.json`; release asset URLs returned HTTP 206 for range download checks, and the remote manifest hash matched the local generated manifest.
- [x] The 1.4.11 macOS DMG was rebuilt after a Finder `-36` copy failure report; CI now stages the app bundle with `ditto`, mounts the generated DMG, copies `UniLink Control.app` back out, verifies the executable, and runs `hdiutil verify` before uploading.
- [~] Android physical automatic update to 1.4.12 passed on 2026-07-15. Windows 1.4.11 found 1.4.12 but its Rust/reqwest download stream failed after about 15 MB; the old downloader had no retry or resume. Windows now retries, resumes with HTTP Range, verifies SHA-256 before install, and retries an initially failed update check. The forced-disconnect resume test and checksum test passed, the repaired 1.4.12 asset and manifest were published, and this PC was bootstrapped to installed version 1.4.12+70 with a matching built DLL hash. A future real 1.4.12 -> newer-version automatic update is still required before Windows is fully accepted. macOS physical automatic update remains unverified.
- [~] The Intel Mac was manually bootstrapped from RustDesk/UniLink 1.4.8 to UniLink Control 1.4.12 build 70 on 2026-07-15. The old application and configuration were backed up, identity-bearing configuration hashes matched after migration, the GUI/user server/root service run from the new bundle, and LAN port 21118 is reachable. The published DMG exposed two release defects: the service binary was copied after app signing, invalidating strict code-sign verification, and the daemon plist used a shell command with an unquoted app path containing spaces. Source now re-signs and verifies after adding the service, verifies the finished DMG copy, and executes the service directly. A corrected DMG still needs a real Mac rebuild and publication. The Mac also has no routed internet through its current Ethernet gateway, so GitHub and rendezvous DNS checks time out until its network path is repaired.
- [~] The upgraded Mac's new bundle ID required fresh macOS Screen Recording and Accessibility approval. Before approval, direct authentication succeeded but capture stayed at `Invalid display stream 0x0`. After approval and a clean single-instance user-server restart, a physical Windows -> Mac LAN session created a 1680x1050 VP9 video service and displayed the desktop continuously. Future upgrades must preserve or clearly request these permissions and avoid launching duplicate server instances during restart.
- [~] UniLink Control 1.4.13+71 release candidate enables Windows `hwcodec,vram` and macOS `hwcodec`, fixes duplicate macOS `--server` startup handling, and has a verified Windows installer plus a passing focused Rust decision test. macOS and Android artifacts are not yet built or published, so the real 1.4.12 -> 1.4.13 automatic-update path remains unverified.
- [x] UniLink Control 1.4.14 served as the Windows field build and was manually upgraded to Program Files `1.4.15+73` on 2026-07-18; 1.4.14 was not published as a coordinated three-platform release.
- [~] 1.4.15 Windows installation consistency: controlled migration, configuration backup, stale AppData executable disabling, Program Files launch paths, startup identity logging, and same-version reinstall passed. Reboot, uninstall recovery, and a real GitHub 1.4.14 -> 1.4.15 automatic update remain required.
- [~] LAN routing isolation is present in the Windows 1.4.14 field build: direct IP targets ignore implicit relay/WebSocket/proxy settings and 2 focused Rust tests passed. Explicit route intent, hostname handling, prevention of derived relay state persistence, and physical route-switching regression move to the 1.4.15 gate.
- [ ] Existing UniLink/TigerVNC black-screen and Mac system-network repair are explicitly deferred from 1.4.15 by the 2026-07-17 product decision. Any new regression caused by 1.4.15 still blocks release.
- [ ] 1.4.15 coordinated release: align Windows/macOS/Android to `1.4.15+73`, verify compatibility and route isolation, build all three artifacts, complete Windows/Android automatic updates plus Mac LAN manual upgrade, and publish one matching `latest.json`.
- [ ] Establish a repeatable signed Windows release process.
- [ ] Establish a repeatable signed/notarized macOS release process.
- [~] Android release APK for 1.4.11 is built and published with SHA-256 verification; permission explanation, installation/update policy, and trusted distribution path still need product copy and real-device validation.
- [~] Verify each platform checks real GitHub Release metadata and receives the intended artifact. Android physical update passed. Windows remote 1.4.12 asset/manifest digests and local bootstrap install passed; a subsequent automatic version transition remains. The Mac manual bootstrap passed, but automatic update, corrected-DMG publication, and a working Mac internet path remain.
- [x] Release manifest generation and publishing flow produced `latest.json` with Windows/macOS/Android SHA-256 values for 1.4.11.

Acceptance: a nontechnical user can install, trust, update, and recover each platform without guesswork.

## Execution Order

1. Complete Section A regression until basic remote control is demonstrably stable.
2. Complete Section B connection decision and device states.
3. Complete the crop-and-input portion of Section D.
4. Complete Section C file/clipboard reliability.
5. Build Section F unified LAN/native-service paths.
6. Finish functional UI/settings audit in Section G.
7. Ship release/update work in Section H.

Current release decision: treat 1.4.14 as a Windows field build and make `1.4.15+73` the next coordinated Windows/macOS/Android release. Keep automatic updates disabled until the 1.4.15 single-install, compatibility, route-isolation, artifact, and recovery gates pass. Existing black-screen work and Mac system-network repair are deferred, not claimed as fixed.

Priority override: if the user reports a failure in basic remote control, file transfer, authentication, or installation, stop feature work and repair that foundation first.
