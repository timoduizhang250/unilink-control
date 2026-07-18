# UniLink Control Handoff - 2026-07-15

## Windows Update Failure and Repair

Android physically updated to 1.4.12. Windows 1.4.11 read the same valid manifest and found 1.4.12, but its Rust/reqwest GitHub Release download failed after about 15 MB with `error sending request for url`. The old Windows downloader had no retry or resume, so a transient TLS/stream failure discarded the update. This was not a Windows permission, account, or manifest problem.

Implemented in:

- `src/common.rs`: retain the selected platform SHA-256 with update state.
- `src/hbbs_http/downloader.rs`: eight attempts, backoff, HTTP Range resume, clean restart when Range is ignored, and final-flush completion safety.
- `src/updater.rs`: shared resilient downloader, SHA-256 verification, invalid-cache removal, and retry after an initial check failure.
- `src/flutter_ffi.rs`: verify Windows/macOS artifacts before install or extraction.

## Verification

- Targeted `rustfmt --check`: passed.
- Downloader tests: 2 passed, including a local server that deliberately drops the first response halfway and then serves the remainder by Range.
- Updater SHA-256 test: passed.
- Windows Rust Release build: passed.
- Flutter Windows Release build: passed.
- Windows portable/update package build: passed.
- Published Windows 1.4.12 asset SHA-256: `0d8c21e7bdc9056e760a75a91c7ee426501042c054463b77a6573fd4d69e61b3`.
- GitHub remote asset digest and downloaded remote `latest.json` hash matched; the macOS and Android manifest entries were preserved.
- This PC was bootstrapped from installed `1.4.11+69` to `1.4.12+70`. The installed `librustdesk.dll` hash matched the just-built DLL.

Windows is repaired and running the resilient updater, but do not mark Windows automatic update fully accepted until a future real `1.4.12 -> newer` update completes through the automatic path.

## Publication State

- Release: `https://github.com/timoduizhang250/unilink-control-releases/releases/tag/1.4.12`
- The repaired Windows asset and `latest.json` are live.
- Local source commit: `5c845ff` in worktree `D:\agents\codex\unilink-release-1.4.12`.
- Source push failed because `timoduizhang250/unilink-control` no longer exists in the authenticated GitHub account. The release repository still exists and received the binaries. Preserve the local commit until a source repository is recreated or another source remote is selected.

## Workspace Safety

The main workspace remains intentionally dirty with unrelated connection, UI, Android, and release work. Do not reset, clean, revert, or broadly stage it. The updater source changes are also present there and were tested from that workspace.

## Intel Mac Manual Bootstrap

The Mac at `192.168.137.2` was still running RustDesk/UniLink 1.4.8 build 66 from `/Applications/RustDesk.app`. Its old client did not have the current GitHub update path. The published 1.4.12 x86_64 DMG was uploaded over SSH and verified on the Mac with SHA-256 `1dba72b5035f66ac70dbdb4d189c9c67fa2c009bb44e2245c04bd67a66c0bda6`.

The DMG contained UniLink Control 1.4.12 build 70, but strict code-sign verification failed because `Contents/MacOS/service` had been added after signing. After staging and local ad-hoc re-signing, strict deep verification passed. Installation then exposed a second defect: the daemon plist launched the service through `/bin/sh -c`, so the unquoted `UniLink Control` path was split at the space. The installed daemon plist was corrected to execute the service directly.

Physical result:

- `/Applications/UniLink Control.app` reports 1.4.12 build 70.
- The old app remains at `/Applications/RustDesk 1.4.8 Backup 20260715-135920.app`.
- Backups and generated pre-migration configuration are under `/Users/hp/Downloads/UniLink-1.4.8-Backup-20260715-135920`.
- Legacy RustDesk identity/config files were migrated to the actual normalized directory `/Users/hp/Library/Preferences/com.hanako.UniLink-Control`; the identity-bearing config hash matched the old file.
- New GUI, `--server`, and root `service` processes are running from the UniLink bundle.
- TCP `192.168.137.2:21118` is reachable from Windows.

Source changes now make the daemon execute `service` directly and make the macOS build re-sign and strictly verify the app after copying `service`, run `hdiutil verify`, and strictly verify the app copied back from the finished DMG. Python syntax and plist XML checks passed on Windows, and the equivalent signing/service corrections passed on the physical Mac. A fresh Mac build has not run because that Mac currently has no Rust/Flutter toolchain.

The Mac's current Ethernet default route is `192.168.137.1`, but it has no raw internet connectivity through that gateway. GitHub and `rs-ny.rustdesk.com` DNS/HTTPS checks time out. The manual LAN bootstrap is complete, but future automatic updates and public-line registration require a working Mac internet path.

## Mac Permission and Direct-Control Recovery

After the user disabled macOS Remote Management, SSH remained reachable while Screen Sharing port 5900 stopped listening. Remote Management was re-enabled for user `hp`, restoring port 5900. UniLink direct port 21118 remained reachable throughout.

The upgraded `com.unilink.control` bundle then authenticated over LAN but stayed black at "waiting for video". The macOS TCC database showed the old `com.carriez.rustdesk` bundle approved while `com.unilink.control` Screen Recording was denied. System logs repeated `Invalid display stream 0x0`. The old signed 1.4.8 backup was temporarily used as a rescue capture path so the user could approve Screen Recording and Accessibility for the new UniLink bundle. The temporary `/Applications/RustDesk.app` rescue link was removed afterward; the backup app remains untouched.

Switching back initially created duplicate UniLink listeners because the launch agent and manual GUI starts overlapped. Logs showed `Address already in use (os error 48)` and the launch agent repeatedly exited with code 255. The user-side processes and UniLink IPC directory were stopped cleanly, then the launch agent was bootstrapped once. Final state:

- TCC reports Screen Recording and Accessibility approved for `com.unilink.control`.
- One stable `/Applications/UniLink Control.app/Contents/MacOS/UniLink Control --server` process listens on port 21118.
- The root service remains active from the 1.4.12 bundle.
- Windows established a LAN session to `192.168.137.2:21118`.
- Server logs created a 1680x1050 capture and VP9 encoder, and the Windows client displayed the live Mac desktop for repeated visual checks.

Pointer, drag, keyboard, deliberate disconnect, and reconnect remain to be recorded before the full Windows -> Mac path is marked verified.

## UniLink 1.4.13 Release Preparation

- Version sources are aligned at `1.4.13+71` for Rust, Flutter, and the Windows portable packer.
- Windows Rust Release and Flutter Release builds passed with `hwcodec,vram,flutter`.
- `rustdesk-1.4.13-install.exe` was produced at 27,163,648 bytes with SHA-256 `a8c211da33ad56f41e9811a49daf28e1facc15e62df7f04d88acccfecd8436c2` and file/product version 1.4.13.
- The packaged and Cargo-built `librustdesk.dll` files matched at SHA-256 `e9c9148760b3f1d9de0ba1607f382898d378bf8b7855a3b56a808136124e0184`.
- Focused test `server::ipc_start_failure_tests::macos_duplicate_exits_successfully_only_for_a_healthy_incumbent` passed with the Windows hardware-codec feature set.
- macOS packaging now enables `hwcodec`, signs after adding the service binary, verifies the app and DMG, and keeps the bounded Cargo cache step.
- `patches/unilink-hbb-common.patch` was regenerated from the current submodule diff; reverse-apply verification passed and its SHA-256 is `78efc269a2375eece40053b0b80ba5d03acab8970b008a43b15078114ae79e13`.

Publication is not complete. The current restricted execution account cannot read the existing Android signing key, cannot see the user-owned WSL Ubuntu distribution, and its GitHub CLI token returns HTTP 401. Do not replace the Android signing key because existing installations must remain upgrade-compatible. Keep this Windows PC on installed 1.4.12 until the published 1.4.13 automatic update is exercised.

## Windows Mixed-Installation Finding - 2026-07-16

The Windows PC is currently running more than one UniLink installation:

- Program Files GUI/tray/service: `C:\Program Files\UniLink Control`, version 1.4.12+70.
- Per-user GUI: `C:\Users\温工\AppData\Local\Programs\UniLink Control`, version 1.4.11+69.
- The desktop shortcut and the per-user Start Menu shortcut still launch the 1.4.11 GUI, while the startup tray and service launch from Program Files.

The user's successful connection is therefore useful as a connectivity result, but it is not a clean 1.4.12/1.4.13 regression test. The installation-consistency repair is deferred to 1.4.14. Until that work is completed, keep automatic updates disabled, preserve the currently working state, and do not remove the old per-user installation without a controlled backup and launch-path migration.
