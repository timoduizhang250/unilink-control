# UniLink Control Final Test Matrix

Status: prepared for the final integrated test pass

Run this matrix only after installing the current Windows Release build and
Android debug/release candidate. Record the exact build version and date next
to each result.

## 1. Basic Remote Control

| Route | Required result |
| --- | --- |
| Windows -> Windows Quick Support | ID is found, password prompt opens, desktop appears, pointer/keyboard/clipboard work, reconnect works. |
| Windows -> Mac | Desktop appears, pointer/keyboard/clipboard work, reconnect works. |
| Android -> Windows | Desktop appears, touch/keyboard/disconnect/reconnect work. |
| Android -> Mac | Desktop appears, touch/keyboard/disconnect/reconnect work. |

Record public server line, whether direct or relay was used, and any error code.

## 2. My Devices And Connection Choice

1. Add or expose a Windows, Mac, and Android device in My Devices.
2. Verify online/offline state refreshes.
3. Open the connection decision panel.
4. Confirm UniLink remote control is the primary action.
5. On a LAN, confirm SSH, drive, RDP, or VNC appears only when its port is reachable.
6. Verify public-server connection, SSH, drive, RDP, and VNC actions open the intended flow.

## 3. Mac Window Mode

1. Connect Windows -> Mac and open `Extract Mac window`.
2. Select a window on the primary display; confirm only that window is shown.
3. Click, drag, scroll, type, resize, refresh bounds, and close the extracted view.
4. Confirm the original full-desktop session remains full desktop.
5. Move a target window to a second display; repeat steps 2-4.
6. Repeat on a Retina or mixed-DPI display when available.

## 4. Files And Clipboard

1. Drop a file from Windows onto a Mac remote desktop and verify Finder receives it.
2. Select a Finder file, prepare drag-out, and drag it into Windows Explorer.
3. Select a symlink or an unsupported Finder item and verify UniLink reports that no downloadable file was produced instead of hanging.
4. Copy plain text and a file in both directions.
5. Disable clipboard or file transfer in settings and confirm the disabled capability is actually unavailable.

## 5. Local Network And Native Services

Result record, 2026-07-12:

- Windows -> Mac VNC: passed. UniLink reached `192.168.137.2:5900`, found TigerVNC, launched `vncviewer.exe`, and the user entered the Mac desktop successfully.

1. Android -> Windows with Windows RDP enabled: choose LAN connection -> Windows RDP and verify the installed RDP client opens.
2. Android -> Mac with Screen Sharing enabled: choose LAN connection -> Mac VNC and verify the installed VNC client opens.
3. Windows -> Windows with RDP enabled: verify My Devices can probe and launch `mstsc`.
4. Windows -> Mac with Screen Sharing enabled: verify My Devices can launch registered VNC/Screen Sharing.
5. Windows Home target: verify RDP is described as unavailable and Quick Support is used instead.
6. Android target: verify UniLink Agent permissions are required and no agentless-control claim appears.

## 6. Settings And Update

1. Toggle full control, clipboard, file transfer, terminal, audio, image quality, auto update, and server line; close and reopen settings to verify persistence.
2. Confirm every visible settings button opens a real page, dialog, or system action.
3. Build and publish a signed Windows installer, a signed/notarized Mac DMG, and an Android release APK/AAB.
4. Upload artifacts plus `latest.json` with non-empty SHA-256 values to the release channel.
5. Install an older build on each platform and verify update discovery, download, and restart/update behavior.

## Required Evidence Before Marking Release Ready

- Windows Release installer hash and test result.
- macOS signed/notarized DMG hash and test result.
- Android signed APK/AAB hash and install result.
- GitHub Release URLs and the final `latest.json`.
- A completed result for every row above, including direct/relay observations.
