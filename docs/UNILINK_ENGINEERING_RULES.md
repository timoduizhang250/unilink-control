# UniLink Control Engineering Rules

Updated: 2026-07-11
Status: Binding working rules

## Mandatory Read Before Every UniLink Task

Before investigating, planning, editing, testing, or reporting work on UniLink, read in this order:

1. `docs/UNILINK_PRODUCT_CHARTER.md`
2. This file
3. `docs/UNILINK_EXECUTION_CHECKLIST_ANDROID_WINDOW.md`
4. The newest `docs/UNILINK_HANDOFF_*.md` when deployment, test evidence, or current operational state is relevant.

At the start of substantive work, state briefly which stage of the checklist is being handled. If the user's newest request changes product direction, update the charter and checklist before implementing conflicting work.

## Truth and Acceptance Rules

- "Completed" means the code is present, builds on the relevant platform, and has passed the stated verification level.
- "Implemented" means code exists but has not yet been verified in the required environment.
- "Ready for user test" means a build or installable package exists and the exact test path is known.
- Do not present an unverified integration, a visual mock, or a nonfunctional button as a delivered capability.
- Preserve the distinction between UniLink native control, protocol handoff, and a target system's own service.

## Scope and Product Rules

- UniLink's product goal is cross-device continuity, not protocol launching.
- Remote control, LAN, RDP, VNC, SSH, SFTP, SMB, public servers, and updates are foundation layers that must support the core experience.
- Keep protocol mechanics behind intent-oriented flows whenever possible.
- Do not add a page, setting, or menu merely to expose an internal capability. It must support a real user workflow.
- Do not change unrelated UI, settings, names, or behavior while addressing a narrow task.

## Worktree Safety

- Never reset, clean, revert, or delete unknown worktree changes.
- Assume unrelated changes belong to the user or earlier work; inspect and work around them.
- Use targeted diffs and targeted verification. Avoid broad formatting or metadata churn.
- When a documented edit tool is blocked by the environment, use the narrowest safe fallback and explicitly verify the changed files.

## Architecture Rules

- Keep UniLink-specific Flutter code in `flutter/lib/hanako/` or clear UniLink page modules.
- Page widgets own layout and user actions; business logic belongs in focused services, helpers, or models.
- Rust/RustDesk core owns transport, video, input, session behavior, system integration, and update primitives. Flutter owns UI state and presentation.
- Platform-specific behavior belongs in explicit platform layers or narrow branches, not a hidden generic path.
- New bridge methods must have intent-revealing names, defined inputs/outputs, and failure behavior.
- New settings must state key name, default value, supported platforms, persistence location, and whether the UI reads the stored value back.

## Connection Rules

- Never regress normal UniLink remote control, file transfer, or authentication while adding a new path.
- Prefer a single connection decision flow: reuse an existing UniLink session when appropriate, use LAN direct paths when available, and use native services only where supported and configured.
- Windows RDP and macOS Screen Sharing/VNC are native-service handoffs unless and until UniLink embeds a verified native protocol engine.
- Android remote control requires a target-side authorized agent. Do not promise agentless Android control.
- Every failure surface must distinguish, where possible: target offline, network unreachable, service unavailable, permission missing, authentication failed, client app missing, or unsupported platform.

## Frontend Rules

- Every interactive element must have a real action and visible feedback: progress, result, error, or navigation.
- Use Chinese user-facing copy in the current product UI unless the user changes the language plan.
- Keep the home page focused on devices and high-frequency continuity actions. Put advanced setup and diagnostics in settings or contextual dialogs.
- Use existing UniLink theme tokens and component patterns. Do not introduce an unrelated visual system while implementing a functional task.
- Mac window mode is an in-session advanced capability. It must never degrade normal remote desktop control.

## Files, Clipboard, and Storage Rules

- Clearly distinguish Windows-to-Mac upload, Mac Finder selection download, and true system-level drag-and-drop.
- SSH/SFTP is a direct-reachability capability, not a substitute for public relay transport.
- SMB mounting must report whether a failure is caused by network reachability, credentials, or share configuration.
- Do not claim seamless file movement until the tested workflow actually completes on both endpoints.

## Mac Window Mode Rules

- Short-term delivery is: window metadata, remote image crop, correct input coordinate mapping, and a separately managed UniLink remote window.
- Coordinate logic must explicitly account for local window coordinates, remote rendered image coordinates, macOS display coordinates, crop offset, DPI, scale, and multi-display layout.
- Visual crop without correct pointer, drag, scroll, and keyboard delivery is incomplete.
- Advanced window behavior must fall back safely to normal remote control.

## Build and Verification Rules

- Format and analyze changed Dart files.
- Build the touched target platform before reporting a buildable delivery.
- When a physical device is available, verify the concrete flow instead of only compiling.
- UI changes must be viewed in the relevant application, not only inspected as source.
- Do not widen a task to clean old warnings unless they block the requested work.
- For release/update work, verify version source, artifact URL, checksum/signing, fallback behavior, and what an existing user will actually receive.

## Delivery and Update Rules

- After each coherent, user-facing batch of UniLink changes has been built and verified at its applicable level, publish its installable artifacts and `latest.json` to `timoduizhang250/unilink-control-releases` before asking the user to update.
- Do not publish a source-only change as an automatic update. Windows requires its installer artifact; macOS requires the matching `.dmg`; Android requires its signed package.
- Keep releases purposeful: closely related fixes may be delivered together after verification, but do not leave a verified user-facing change only in the local workspace.
- When a platform artifact is unavailable, state that platform's update status plainly instead of implying it has received the release.
