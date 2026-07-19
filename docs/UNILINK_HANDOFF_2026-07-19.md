# UniLink Control Handoff - 2026-07-19

Active stage: 1.4.15 publication completed at the artifact level. Physical automatic-update and cross-device regression gates remain open.

## Source Publication

- Source repository: <https://github.com/timoduizhang250/unilink-control>.
- Release branch: `release/1.4.15`.
- Release source commit: `07cfa79c48ce0565f5812f8fdd51775b6204d38e`.
- The same commit was fast-forwarded to `main` after the Intel macOS workflow passed.
- Mac workflow: <https://github.com/timoduizhang250/unilink-control/actions/runs/29633139356>.

## GitHub Release

- Public release: <https://github.com/timoduizhang250/unilink-control-releases/releases/tag/1.4.15>.
- Published version: `1.4.15+73`.
- `latest.json` is public and points to the three matching 1.4.15 assets.

Artifacts:

- Windows x86_64 EXE: 27,160,576 bytes, SHA-256 `b41411ab99faec9f2a53ad392bc32fc385c188416089049b0bb29f2465ea2153`.
- Intel macOS DMG: 37,225,966 bytes, SHA-256 `7653e6f7967d59819bb91519ed8d92a75e4189c7530ead23491b77dce359de39`.
- Android arm64 APK: 63,357,365 bytes, SHA-256 `aed012a60a18a5d60717ff43547e4a5c023bf5180b70232e445e258f27f793cf`.
- `latest.json`: 984 bytes, SHA-256 `9b02afe9d13f19d1c53d73e8ff17f876a2590b807a42cdfe60c8681cff5dabbf`.

All four public assets were downloaded again through the GitHub asset API after publication. Their downloaded sizes and SHA-256 values matched the public manifest and GitHub asset digests.

## Build and Test Evidence

- Windows formal installer build and Program Files migration passed as recorded in `UNILINK_HANDOFF_2026-07-18.md`.
- Android release package verification passed for package `com.unilink.control`, version code 73, version name 1.4.15, and the UniLink Control release certificate.
- Intel macOS GitHub Actions completed DMG verification, mounted-copy executable verification, and strict code-sign verification.
- Flutter public-connection policy tests passed: 8/8.
- Rust direct-peer routing tests passed: 2/2.
- Windows platform migration tests passed: 6/6.

## Remaining Acceptance Gates

- Windows has not completed a real older-public-release to 1.4.15 automatic-update download/install test.
- Android has not completed a physical old-version to 1.4.15 automatic-update test because no ADB device was connected during publication.
- Mac has not been manually upgraded over LAN from 1.4.12 to 1.4.15.
- Cross-version and cross-device remote-control regression remains open.
- Existing UniLink/TigerVNC black-screen work and Mac USB Wi-Fi repair remain deferred and are not claimed as fixed.
