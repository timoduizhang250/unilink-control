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
