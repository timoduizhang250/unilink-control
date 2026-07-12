# UniLink Control Product Charter

Updated: 2026-07-11
Status: Active source of truth

## Product Positioning

UniLink Control is a cross-device continuity product. Its purpose is to make a user's Windows, macOS, and Android devices feel like one connected work environment.

The desired experience is not "open a remote desktop tool." It is "continue working from another device": see the right device, reach the right application and file, and keep working with minimal setup or protocol knowledge.

## Product Promise

- Present the user's devices as a coherent personal device space.
- Choose the best available connection path automatically or with plain-language guidance.
- Make screen control, application windows, files, clipboard, storage, and terminal work together across Windows, macOS, and Android.
- Preserve the normal local experience whenever possible. A remote Mac window should ultimately behave like a local window, not merely a cropped remote desktop.
- Be honest about platform limits, permissions, and failures.

## What Is Not the Product Positioning

RDP, VNC, SSH, SFTP, SMB, public relay servers, LAN discovery, device IDs, and automatic updates are implementation and connection capabilities. They are important foundations, but UniLink is not positioned as an RDP launcher, VNC viewer, or RustDesk reskin.

## Capability Layers

### 1. Seamless Workspace (product core)

- My devices and recent work.
- Continue a session from another device.
- Mac window mode and eventual native-feeling remote windows.
- Cross-device files, clipboard, drives, and terminal workflows.
- One coherent experience across public network and LAN.

### 2. Connection Foundation

- UniLink ID connection over public servers or relay.
- LAN discovery and direct connection.
- Native protocols when they provide the best legitimate route: RDP for Windows, Screen Sharing/VNC for macOS.
- UniLink Android agent connection for Android targets.
- Network health, authentication, fallback, and clear error states.

### 3. Platform Boundaries

- A Windows or macOS target can be reachable without UniLink only after that operating system's own remote service has been enabled and authorized.
- Android targets require UniLink or another authorized device-side agent for screen capture and input. Do not claim an Android device can be remotely controlled without a target-side app and permissions.
- Never imply that a LAN cable, IP address, or SSH password bypasses operating-system authorization.

## Primary User Model

The user owns the devices and may not know technical terms. UniLink must guide by intent:

- "Connect my computer" instead of leading with protocol names.
- "Use the fastest local connection" instead of leading with LAN/IP details.
- Ask for IP, username, ports, or permissions only when automatic discovery cannot complete the connection.
- Explain failure in user language and state the next useful action.

## Experience Principles

- Basic remote control must remain reliable before advanced polish ships.
- Do not make the home page into a settings page or a protocol dashboard.
- A visible control must perform its named action and show feedback.
- Prefer automatic connection selection, but allow an understandable manual path.
- Use "My Devices" as the primary mental model. Connection methods belong behind the device action.
- Advanced capabilities, including Mac window mode, live inside a remote session rather than competing with the primary home flow.

## Product Success Criteria

1. A user can find their own device and start a stable remote session without understanding servers or protocols.
2. Files, clipboard, windows, and input flow naturally enough that switching devices does not interrupt work.
3. The app clearly distinguishes verified functionality, unavailable platform capability, and a required permission or setup action.
4. Public-network and LAN usage feel like variations of one product, not separate applications.
