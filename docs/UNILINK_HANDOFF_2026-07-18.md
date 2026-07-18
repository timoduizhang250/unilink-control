# UniLink Control Handoff - 2026-07-18

Active stage: 1.4.15 first batch, version and Windows installation root. Existing black-screen work and Mac system-network work remain explicitly deferred.

## Version and Build Metadata

- Root Rust, portable Rust, and Flutter versions are `1.4.15+73`.
- `build.rs` rejects Cargo/Flutter version mismatches and exposes build number 73 through `UNILINK_BUILD_NUMBER`.
- `build.py` validates root Cargo, portable Cargo, and Flutter versions before building.
- `cargo check --offline --release --lib --features flutter,hwcodec,vram` passed in the VS x64 environment.
- Six focused Windows platform tests passed, including migration command packaging and quoted service startup.

## Windows Build

- Installer: `rustdesk-1.4.15-install.exe`.
- Installer SHA-256: `B41411AB99FAEC9F2A53AD392BC32FC385C188416089049B0BB29F2465EA2153`.
- Installed/main executable version: `1.4.15+73`.
- Main executable SHA-256: `A62B5A0E7ED64C11C24017F2B1B4733DE2F4C493631573901F5D08969883FDA0`.
- Core `librustdesk.dll` SHA-256: `5DBEA4E6498A41760FDE70A4AEED12C92D29E21C247248577E9F5E0DADE9D673`.
- The packaged migration script hash matches `scripts/unilink_windows_install_migration.ps1`.

The Windows build required an ASCII physical Cargo home at `D:\agents\codex\.cargo-unilink`, because NASM cannot consume dependency include paths under the Chinese Windows user profile. The build must also set `VCPKG_ROOT=D:\tools\vcpkg` and load the Visual Studio x64 developer environment.

## Migration Verification

- Pre-install state was Program Files `1.4.14+72` plus AppData `1.4.11+69`.
- The formal installer upgraded Program Files to `1.4.15+73`.
- The old AppData executable was renamed to `UniLink Control.exe.disabled-20260718-103729`; it was not deleted.
- Latest migration evidence after idempotent reinstall: `C:\Users\温工\AppData\Local\UniLink Control\MigrationBackups\20260718-121730-50648`.
- All files copied into the migration configuration backup matched the live configuration after install and reinstall.
- Desktop, Start Menu, Startup tray, and service paths point to `C:\Program Files\UniLink Control\UniLink Control.exe`.
- Service state is Running and its path is `"C:\Program Files\UniLink Control\UniLink Control.exe" --service`.
- Startup logs verified `1.4.15+73`, executable path, platform, and the matching core DLL hash for silent-install and tray roles.

PowerShell `Start-Process -Wait` waits for the installer process tree, including the intentionally persistent tray, and therefore appeared to hang after a successful install. `scripts/update_user_build.ps1` now starts the installer without `-Wait`, calls `.WaitForExit(180000)` on the direct installer process only, and then verifies the installed version and service path. Direct-process exit completed successfully during the same-version reinstall test.

## Verification Boundary

- This was a local formal-installer upgrade, not a GitHub automatic-update test.
- Windows has not been rebooted after the migration.
- Uninstall and failure rollback have not been physically tested.
- Basic remote control, file transfer, Android, and Mac regressions were not run in this batch.
- macOS DMG, Android APK, and a 1.4.15 `latest.json` have not been built or published.
- The repository remains intentionally dirty with earlier UniLink work; no reset, clean, or unrelated revert was performed.
