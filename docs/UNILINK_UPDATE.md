# UniLink Control Update Releases

## Decision

UniLink Control does not need to open-source the main codebase for auto update.
Use a separate public release-only repository or static hosting location for update
metadata and installers. Keep the source repository private until the product,
license, and security boundaries are ready.

Default manifest URL:

```text
https://github.com/timoduizhang250/unilink-control-releases/releases/latest/download/latest.json
```

The default can be overridden with:

```text
UNILINK_UPDATE_MANIFEST_URL
```

or the local option:

```text
unilink-update-manifest-url
```

## Manifest

`latest.json` is intentionally static so it can live on GitHub Releases,
GitHub Pages, or any HTTPS host.

```json
{
  "version": "1.4.9",
  "release_url": "https://github.com/timoduizhang250/unilink-control-releases/releases/tag/1.4.9",
  "windows": {
    "x86_64": {
      "url": "https://github.com/timoduizhang250/unilink-control-releases/releases/download/1.4.9/UniLink-Control-1.4.9-x86_64.exe",
      "sha256": ""
    }
  },
  "macos": {
    "x86_64": {
      "url": "https://github.com/timoduizhang250/unilink-control-releases/releases/download/1.4.9/UniLink-Control-1.4.9-x86_64.dmg",
      "sha256": ""
    },
    "aarch64": {
      "url": "https://github.com/timoduizhang250/unilink-control-releases/releases/download/1.4.9/UniLink-Control-1.4.9_aarch64.dmg",
      "sha256": ""
    }
  }
}
```

## Release Flow

1. Build the full installer/portable release artifact, not only the per-user
   copied install folder.
2. Create a GitHub Release in the release-only repository, tagged with the
   target version.
3. Upload the Windows and macOS artifacts.
4. Generate and upload `latest.json` for the newest stable version.
5. The client checks `latest.json`, compares `version` with `crate::VERSION`,
   downloads the matching platform asset, and reuses the existing `--update`
   installer flow.

## Delivery Policy

For each coherent, user-facing UniLink change batch, build and verify the
affected platform artifacts, publish them with `latest.json`, then request the
client update. A platform without its matching installer artifact has not been
updated, even when another platform's release has been published.

The first production channel should be stable-only. Add beta/nightly channels
later with separate manifest URLs, for example `latest-beta.json`.

## macOS Notes

The macOS update asset must be a `.dmg` containing `UniLink Control.app`.
`build.py --flutter` creates:

```text
UniLink-Control-<version>-x86_64.dmg
UniLink-Control-<version>-arm64.dmg
```

depending on the build machine architecture.

The Mac build machine needs:

- Full Xcode, not only Command Line Tools.
- Rust/Cargo.
- Flutter with macOS desktop support.
- A signing/notarization setup before public distribution.

The client can read `macos.x86_64` and `macos.aarch64` from `latest.json`.
