# UniLink Control Handoff - 2026-07-17

This is an operational addendum to `UNILINK_HANDOFF_2026-07-16.md`. Foundation reliability remains the active stage; the Mac display change below is not accepted until a physical reboot and monitor test pass.

## Windows Runtime

- The visible Windows GUI was restored to `C:\Program Files\UniLink Control\UniLink Control.exe`, version `1.4.14+72`.
- The Program Files tray and service also remain active. The old AppData `1.4.11+69` GUI was used briefly for an A/B connection attempt, failed in the same way, and was then closed.
- The failed 1.4.11 comparison means the current Windows-to-Mac connection failure is not established as a 1.4.14-only regression.

## Mac DP-to-HDMI Audit

- Target: `192.168.137.2`, macOS 15.2, Intel UHD Graphics 630 device `0x3e91`, SMBIOS `iMac19,1`.
- Loaded graphics support includes Lilu 1.7.3 and WhateverGreen 1.7.1, confirming an OpenCore/Hackintosh graphics path.
- `system_profiler SPDisplaysDataType` listed the GPU but no attached display. IORegistry also had no `AppleDisplay` instance.
- Runtime framebuffer connectors were:
  - `con0`, port 0, HDMI (`00080000`)
  - `con1`, port 5, HDMI (`00080000`), boot display
  - `con2`, port 6, DisplayPort (`00040000`)
- The existing OpenCore config enabled HDMI type patches for `con0` and `con1` but did not patch `con2`. This is a plausible mismatch for a machine whose two external outputs are ports 5 and 6.

## EFI Change

- Internal EFI: `disk0s1` (`NO NAME`). It was mounted read-only for the audit.
- Full backup: `/Users/hp/Downloads/EFI-Backup-DP-HDMI-20260717-100616`.
- Original `config.plist` SHA-256: `178915f40dd3a2242d6f4218c14ad86927c6cfb45ac5d3ca847b87af22ef4caa`.
- Added only these `DeviceProperties` values under `PciRoot(0x0)/Pci(0x2,0x0)`:
  - `framebuffer-con2-enable` = data `AQAAAA==` (`01000000`)
  - `framebuffer-con2-type` = data `AAgAAA==` (`00080000`, HDMI)
- The candidate plist passed `plutil -lint`; its diff contained only those two keys.
- Written `config.plist` SHA-256: `e65a07529cd3cb950c9890a71727e26bc4e5944987ef25b11d0e92f78f8afd77`.
- The EFI volume was synced and unmounted after the write.

## Verification Boundary

- The Mac was deliberately not rebooted. The running kernel still uses the previous connector map.
- After the write, ports 22, 5900, and 21118 remained reachable.
- DP-to-HDMI output, EDID detection, resolution, refresh rate, audio, cold boot, and remote-control black-screen behavior are unverified.
- Software connector mapping cannot make an electrically incompatible passive adapter work. If the monitor remains undetected, test a known-good active DisplayPort-to-HDMI adapter before adding bus-ID or pipe patches.
- Do not claim the Mac display or UniLink black-screen issue is fixed until a physical reboot and monitor test pass. Keep the backup available for immediate rollback.

## DP-to-HDMI Follow-up After Physical Failure

- The user rebooted after the first connector-type patch and reported that the display still had no signal.
- The reboot was confirmed at 2026-07-17 10:11:58. The first patch loaded: all three runtime connectors reported HDMI, but `system_profiler`, `AppleDisplay`, and `IODisplayConnect` still reported no attached display or EDID.
- PCI subsystem `103c:859c` and CPU `i3-8100T` identify the hardware as an HP ProDesk 400 G5 Desktop Mini.
- A same-model success report documents both physical DisplayPort outputs working through DP-to-HDMI cables with audio. Its effective mapping uses the CFL mobile framebuffer already present on this Mac, an HDMI placeholder on connector 0, and physical DP connectors on BusIDs 1 and 2: <https://osxlatitude.com/forums/topic/17263-solved-hp-prodesk-400-g5-mini-monterey-fine-tuning/>.
- A second candidate preserved SMBIOS, device ID, serial identity, Kexts, and all non-display settings while applying this connector map:
  - con0: index 3, BusID 4, pipe 8, HDMI, flags `C7030000`
  - con1: index 1, BusID 1, pipe 9, DP, flags `87010000`
  - con2: index 2, BusID 2, pipe 10, DP, flags `87010000`
- Pre-second-change full backup: `/Users/hp/Downloads/EFI-Backup-DP-HDMI-BusID-20260717-113904`.
- Pre-second-change config SHA-256: `e65a07529cd3cb950c9890a71727e26bc4e5944987ef25b11d0e92f78f8afd77`.
- Second config SHA-256: `0d2aa41bcc84147d7634be34e73e96901db5c7eee6c1fa0c50e605ef74949c22`.
- The second config passed `plutil -lint`; the Mac rebooted at 2026-07-17 11:41:51 and ports 22, 5900, and 21118 recovered.
- Runtime now reports connector 0 as HDMI and connectors 1/2 as DP, but still has no `AppleDisplay`, `IODisplayConnect`, EDID, or display entry in `system_profiler`.

Current conclusion: software patches load and the GPU is accelerated, but the display identification channel is not reaching macOS. Before any further EFI edit, determine whether the monitor shows the HP logo/OpenCore picker during power-on. No pre-OS image indicates cable direction, passive-adapter compatibility, monitor input selection, or hardware failure; use a known-good active adapter explicitly rated for DisplayPort source to HDMI display. If pre-OS video works but disappears only when macOS starts, capture the exact monitor model and EDID for a timing/EDID override investigation.

## DP-to-HDMI Resolution

- The user confirmed that verbose OpenCore/macOS boot text was visible and the monitor lost signal only when macOS took over the Intel graphics driver. This proved that the cable direction and pre-OS video path worked.
- The same-model success report also faked the physical UHD 630 device to the framebuffer device ID. The third candidate added only `device-id = mz4AAA==` (`0x3e9b`).
- Third-change backup: `/Users/hp/Downloads/EFI-Backup-DP-HDMI-DeviceID-20260717-115045`.
- Third config SHA-256: `422a68dda8773a4d2f1afb83b3bfc89f3f24cf378688fef9a516b29217762517`.
- After the third reboot, `system_profiler` correctly reported device ID `0x3e9b`, but the monitor still had no EDID or display object.
- The final candidate kept the verified BusID/index/pipe map and device ID, then changed physical connectors 1 and 2 from DP/default flags to HDMI/TMDS flags:
  - con1 type `00080000`, flags `C7030000`
  - con2 type `00080000`, flags `C7030000`
- Final-change backup: `/Users/hp/Downloads/EFI-Backup-DP-HDMI-TMDS-20260717-142359`.
- Pre-final config SHA-256: `422a68dda8773a4d2f1afb83b3bfc89f3f24cf378688fef9a516b29217762517`.
- Final config SHA-256: `09f33db460be0e81bab424ce9edeca53661e9566413294825540015837570cbd`.
- The final plist passed validation and the Mac rebooted at 2026-07-17 14:25:46.
- Physical display detection passed at the system level after reboot: 1920x1080 at 60 Hz, 30-bit color, main display, online, mirror off. `AppleDisplay` and `IODisplayConnect` objects were present.
- Ports 22, 5900, and 21118 recovered and remained reachable.

The working display fix requires all three pieces together: the BusID/index/pipe connector map, the `0x3e9b` device-ID injection, and HDMI/TMDS type plus flags on both physical DP connectors. Preserve these values during future OpenCore or WhateverGreen updates. A visible physical check and HDMI-audio check are still useful, but macOS display enumeration and online status are verified.
