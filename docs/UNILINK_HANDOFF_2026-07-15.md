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
