import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/remote_terminal_runner.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';
import 'package:flutter_hbb/models/model.dart';

class UniLinkMacWindowInfo {
  final String appName;
  final String title;
  final int pid;
  final int index;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool visible;
  final bool serverCropped;

  const UniLinkMacWindowInfo({
    required this.appName,
    required this.title,
    required this.pid,
    required this.index,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.visible,
    this.serverCropped = false,
  });

  String get displayTitle {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle == appName) return appName;
    return '$appName - $cleanTitle';
  }

  String get rectText =>
      '${x.round()}, ${y.round()}  ${width.round()} x ${height.round()}';

  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'title': title,
      'pid': pid,
      'index': index,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'visible': visible,
      'serverCropped': serverCropped,
    };
  }

  UniLinkMacWindowInfo copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    bool? visible,
    bool? serverCropped,
  }) {
    return UniLinkMacWindowInfo(
      appName: appName,
      title: title,
      pid: pid,
      index: index,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      visible: visible ?? this.visible,
      serverCropped: serverCropped ?? this.serverCropped,
    );
  }

  factory UniLinkMacWindowInfo.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? 0;
    }

    int integer(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return UniLinkMacWindowInfo(
      appName: '${json['appName'] ?? ''}',
      title: '${json['title'] ?? ''}',
      pid: integer('pid'),
      index: integer('index'),
      x: number('x'),
      y: number('y'),
      width: number('width'),
      height: number('height'),
      visible: json['visible'] != false,
      serverCropped: json['serverCropped'] == true,
    );
  }
}

class UniLinkMacWindowDisplayProjection {
  final int displayIndex;
  final Display display;
  final Rect sourceBounds;
  final double sourceScale;

  const UniLinkMacWindowDisplayProjection({
    required this.displayIndex,
    required this.display,
    required this.sourceBounds,
    required this.sourceScale,
  });

  Rect toRemotePixels(UniLinkMacWindowInfo window) {
    return Rect.fromLTWH(
      display.x + (window.x - sourceBounds.left) * sourceScale,
      display.y + (window.y - sourceBounds.top) * sourceScale,
      window.width * sourceScale,
      window.height * sourceScale,
    );
  }
}

/// Finds the display which owns a window reported by macOS accessibility APIs.
/// macOS reports window bounds in logical points, while capture metadata can use
/// either logical or physical display origins on mixed-DPI arrangements.
UniLinkMacWindowDisplayProjection? uniLinkMacWindowDisplayProjection(
  UniLinkMacWindowInfo window,
  List<Display> displays,
) {
  final target = Rect.fromLTWH(window.x, window.y, window.width, window.height);
  UniLinkMacWindowDisplayProjection? best;
  var bestScore = -1.0;
  for (var index = 0; index < displays.length; index++) {
    final display = displays[index];
    final scale = display.scale;
    final candidates = <(Rect, double)>[
      (
        Rect.fromLTWH(
          display.x,
          display.y,
          display.width / scale,
          display.height / scale,
        ),
        scale,
      ),
      (
        Rect.fromLTWH(
          display.x / scale,
          display.y / scale,
          display.width / scale,
          display.height / scale,
        ),
        scale,
      ),
      (
        Rect.fromLTWH(
          display.x,
          display.y,
          display.width.toDouble(),
          display.height.toDouble(),
        ),
        1.0,
      ),
    ];
    for (final candidate in candidates) {
      final score = _unilinkMacWindowOverlapScore(target, candidate.$1);
      if (score > bestScore) {
        bestScore = score;
        best = UniLinkMacWindowDisplayProjection(
          displayIndex: index,
          display: display,
          sourceBounds: candidate.$1,
          sourceScale: candidate.$2,
        );
      }
    }
  }
  return best;
}

double _unilinkMacWindowOverlapScore(Rect target, Rect displayBounds) {
  final overlap = target.intersect(displayBounds);
  final area = overlap.width > 0 && overlap.height > 0
      ? overlap.width * overlap.height
      : 0.0;
  return area + (displayBounds.contains(target.center) ? 1e15 : 0.0);
}

class UniLinkMacWindowMode {
  static const _serverCropPath = '/tmp/unilink_control_window_capture_rect';

  static Future<List<UniLinkMacWindowInfo>> listWindows(
    UniLinkEndpointTarget target,
    FFI? sessionFfi,
  ) async {
    if (!target.isMac) {
      throw Exception(translate('Mac window mode supports Mac only'));
    }
    final command =
        "osascript -l JavaScript -e ${_shellQuote(_listWindowsScript)}";
    if (sessionFfi != null) {
      try {
        final text = await UniLinkRemoteTerminalRunner.runShellViaSession(
          sessionFfi,
          command,
        );
        return _parseWindowList(text);
      } catch (e) {
        debugPrint('[UniLinkMacWindowMode] session terminal failed: $e');
      }
    }

    UniLinkSshConnection? connection;
    try {
      connection = await UniLinkSshProfiles.connect(
        target,
        sessionId: sessionFfi?.sessionId,
        sessionFfi: sessionFfi,
      );
      final bytes = await connection.client
          .run(command)
          .timeout(const Duration(seconds: 12));
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      return _parseWindowList(text);
    } finally {
      connection?.close();
    }
  }

  static Future<void> activateWindow(
    UniLinkEndpointTarget target,
    UniLinkMacWindowInfo window,
    FFI? sessionFfi,
  ) async {
    final script = '''
tell application "System Events"
    set targetProcess to first application process whose unix id is ${window.pid}
    set frontmost of targetProcess to true
    try
        perform action "AXRaise" of window ${window.index} of targetProcess
    end try
end tell
''';
    final command = "osascript -e ${_shellQuote(script)}";
    if (sessionFfi != null) {
      try {
        await UniLinkRemoteTerminalRunner.runShellViaSession(
          sessionFfi,
          command,
          commandTimeout: const Duration(seconds: 12),
        );
        return;
      } catch (e) {
        debugPrint(
            '[UniLinkMacWindowMode] session terminal activate failed: $e');
      }
    }

    UniLinkSshConnection? connection;
    try {
      connection = await UniLinkSshProfiles.connect(
        target,
        sessionId: sessionFfi?.sessionId,
        sessionFfi: sessionFfi,
      );
      await connection.client.run(command).timeout(const Duration(seconds: 8));
    } finally {
      connection?.close();
    }
  }

  static Future<UniLinkMacWindowInfo> refreshWindow(
    UniLinkEndpointTarget target,
    UniLinkMacWindowInfo window,
    FFI? sessionFfi,
  ) async {
    final windows = await listWindows(target, sessionFfi);
    return _findSameWindow(windows, window) ?? window;
  }

  static UniLinkMacWindowInfo? _findSameWindow(
    List<UniLinkMacWindowInfo> windows,
    UniLinkMacWindowInfo target,
  ) {
    for (final window in windows) {
      if (window.pid == target.pid && window.index == target.index) {
        return window;
      }
    }
    for (final window in windows) {
      if (window.pid == target.pid &&
          window.title.trim() == target.title.trim()) {
        return window;
      }
    }
    for (final window in windows) {
      if (window.appName == target.appName &&
          window.title.trim() == target.title.trim()) {
        return window;
      }
    }
    return null;
  }

  static Future<void> setServerCropRect(
    UniLinkEndpointTarget target,
    Rect rect,
    FFI? sessionFfi,
  ) async {
    final left = rect.left.round();
    final top = rect.top.round();
    final width = rect.width.round();
    final height = rect.height.round();
    if (width <= 1 || height <= 1) {
      throw Exception('Invalid Mac window crop rect');
    }
    final script =
        'printf "%s\\n" "$left $top $width $height" > $_serverCropPath';
    await _runCommand(target, sessionFfi, 'sh -c ${_shellQuote(script)}');
  }

  static Future<void> clearServerCropRect(
    UniLinkEndpointTarget target,
    FFI? sessionFfi,
  ) async {
    await _runCommand(
      target,
      sessionFfi,
      'rm -f ${_shellQuote(_serverCropPath)}',
    );
  }

  static Future<void> _runCommand(
    UniLinkEndpointTarget target,
    FFI? sessionFfi,
    String command,
  ) async {
    if (sessionFfi != null) {
      try {
        await UniLinkRemoteTerminalRunner.runShellViaSession(
          sessionFfi,
          command,
          commandTimeout: const Duration(seconds: 8),
        );
        return;
      } catch (e) {
        debugPrint('[UniLinkMacWindowMode] session command failed: $e');
      }
    }

    UniLinkSshConnection? connection;
    try {
      connection = await UniLinkSshProfiles.connect(
        target,
        sessionId: sessionFfi?.sessionId,
        sessionFfi: sessionFfi,
      );
      await connection.client.run(command).timeout(const Duration(seconds: 8));
    } finally {
      connection?.close();
    }
  }

  static List<UniLinkMacWindowInfo> _parseWindowList(String text) {
    final decoded = jsonDecode(text.trim());
    if (decoded is! List) {
      throw Exception(translate('Expected a JSON list response'));
    }
    return decoded
        .whereType<Map>()
        .map((item) => UniLinkMacWindowInfo.fromJson(
            item.map((key, value) => MapEntry('$key', value))))
        .where((item) => item.appName.trim().isNotEmpty)
        .toList(growable: false);
  }

  static const _listWindowsScript = r'''
const se = Application("System Events");
const rows = [];
const processes = se.applicationProcesses.whose({ backgroundOnly: false })();

for (const proc of processes) {
  let appName = "";
  let pid = 0;
  try { appName = String(proc.name()); } catch (e) {}
  try { pid = Number(proc.unixId()); } catch (e) {}
  if (!appName || !pid) continue;

  let windows = [];
  try { windows = proc.windows(); } catch (e) {}
  for (let i = 0; i < windows.length; i++) {
    const win = windows[i];
    let title = "";
    let x = 0;
    let y = 0;
    let width = 0;
    let height = 0;
    let visible = true;
    try { title = String(win.name()); } catch (e) {}
    try {
      const pos = win.position();
      x = Number(pos[0] || 0);
      y = Number(pos[1] || 0);
    } catch (e) {}
    try {
      const size = win.size();
      width = Number(size[0] || 0);
      height = Number(size[1] || 0);
    } catch (e) {}
    try { visible = Boolean(win.visible()); } catch (e) {}
    if (width <= 0 || height <= 0) continue;
    rows.push({
      appName,
      title,
      pid,
      index: i + 1,
      x,
      y,
      width,
      height,
      visible,
    });
  }
}

JSON.stringify(rows);
''';

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _macPermissionCheckCommand() {
    const script = r'''
echo "== UniLink Mac SSH/window check =="
printf "Mac short user: "
id -un 2>/dev/null || whoami
printf "Host name: "
hostname 2>/dev/null || scutil --get LocalHostName 2>/dev/null || true
printf "Remote Login: "
systemsetup -getremotelogin 2>/dev/null || echo "Cannot read Remote Login"
echo "SSH allowed-user group:"
dseditgroup -o checkmember -m "$(id -un)" com.apple.access_ssh 2>&1 || true
echo "sshd process:"
pgrep -lf sshd 2>/dev/null || echo "No sshd process seen"
echo "SSH password settings:"
found_ssh_setting=0
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [ -r "$f" ] || continue
  lines=$(grep -E '^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|UsePAM|AllowUsers|DenyUsers)[[:space:]]' "$f" 2>/dev/null || true)
  if [ -n "$lines" ]; then
    found_ssh_setting=1
    printf "%s\n" "$lines" | sed "s#^#$f: #"
  fi
done
if [ "$found_ssh_setting" = "0" ]; then
  echo "No explicit password/allow-user override found"
fi
echo "System Events permission test:"
osascript -e 'tell application "System Events" to count application processes' 2>&1 | sed 's/^/  /'
''';
    return 'sh -c ${_shellQuote(script)}';
  }
}

void showUniLinkMacWindowMode({
  required UniLinkEndpointTarget target,
  FFI? sessionFfi,
  Future<void> Function(UniLinkMacWindowInfo window)? onOpenWindow,
}) {
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Extract Mac window')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: isDesktop ? 560 : 0,
          maxWidth: isDesktop ? 760 : double.infinity,
          minHeight: isDesktop ? 360 : 0,
          maxHeight: isDesktop ? 560 : double.infinity,
        ),
        child: _MacWindowModePanel(
          target: target,
          sessionFfi: sessionFfi,
          onOpenWindow: onOpenWindow,
          closeDialog: close,
        ),
      ),
      actions: [
        dialogButton('Close', onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

class _MacWindowModePanel extends StatefulWidget {
  final UniLinkEndpointTarget target;
  final FFI? sessionFfi;
  final Future<void> Function(UniLinkMacWindowInfo window)? onOpenWindow;
  final VoidCallback closeDialog;

  const _MacWindowModePanel({
    required this.target,
    required this.closeDialog,
    this.sessionFfi,
    this.onOpenWindow,
  });

  @override
  State<_MacWindowModePanel> createState() => _MacWindowModePanelState();
}

class _MacWindowModePanelState extends State<_MacWindowModePanel> {
  late Future<List<UniLinkMacWindowInfo>> _future;
  bool _activating = false;
  bool _opening = false;
  bool _checkingMac = false;

  @override
  void initState() {
    super.initState();
    _future = UniLinkMacWindowMode.listWindows(
      widget.target,
      widget.sessionFfi,
    );
  }

  void _refresh() {
    setState(() {
      _future = UniLinkMacWindowMode.listWindows(
        widget.target,
        widget.sessionFfi,
      );
    });
  }

  Future<void> _activate(UniLinkMacWindowInfo window) async {
    if (_activating || _opening) return;
    setState(() => _activating = true);
    try {
      await UniLinkMacWindowMode.activateWindow(
        widget.target,
        window,
        widget.sessionFfi,
      );
      showToast(translate('Mac window activated'));
    } catch (e) {
      showToast('${translate('Mac window mode failed')}: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _openWindow(UniLinkMacWindowInfo window) async {
    final onOpenWindow = widget.onOpenWindow;
    if (onOpenWindow == null || _activating || _opening) return;
    setState(() => _opening = true);
    try {
      await UniLinkMacWindowMode.activateWindow(
        widget.target,
        window,
        widget.sessionFfi,
      );
      final refreshed = await UniLinkMacWindowMode.refreshWindow(
        widget.target,
        window,
        widget.sessionFfi,
      ).catchError((_) => window);
      await onOpenWindow(refreshed);
      widget.closeDialog();
      showToast(translate('Mac window extracted'));
    } catch (e) {
      showToast('${translate('Mac window mode failed')}: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UniLinkMacWindowInfo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final error = snapshot.error!;
          final authFailed = isUniLinkSshAuthenticationError(error);
          return _MessagePanel(
            icon: Icons.error_outline_rounded,
            title: translate('Mac window mode failed'),
            message: _cleanError(error),
            action: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (authFailed)
                  FilledButton.icon(
                    onPressed: () => unawaited(_editSshLogin(error)),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: Text(translate('Edit SSH login')),
                  ),
                if (widget.sessionFfi != null)
                  OutlinedButton.icon(
                    onPressed: _checkingMac
                        ? null
                        : () => unawaited(_checkMacPermissions()),
                    icon: Icon(
                      _checkingMac
                          ? Icons.hourglass_empty_rounded
                          : Icons.fact_check_outlined,
                      size: 18,
                    ),
                    label: Text(translate('Check Mac permissions')),
                  ),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(translate('Refresh')),
                ),
              ],
            ),
          );
        }
        final windows = snapshot.data ?? const [];
        if (windows.isEmpty) {
          return _MessagePanel(
            icon: Icons.web_asset_off_outlined,
            title: translate('No Mac windows found'),
            message: translate('Open an app window on Mac and refresh.'),
            action: OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(translate('Refresh')),
            ),
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    translate('Choose a Mac window to extract.'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: translate('Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: windows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final window = windows[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      window.visible
                          ? Icons.web_asset_rounded
                          : Icons.web_asset_off_rounded,
                    ),
                    title: Text(
                      window.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(window.rectText),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _activating || _opening
                              ? null
                              : () => unawaited(_activate(window)),
                          child: Text(translate('Bring to front')),
                        ),
                        if (widget.onOpenWindow != null)
                          FilledButton(
                            onPressed: _activating || _opening
                                ? null
                                : () => unawaited(_openWindow(window)),
                            child: Text(translate('Extract this window')),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editSshLogin(Object error) async {
    final saved = await showUniLinkSshProfileDialog(
      target: widget.target,
      sessionId: widget.sessionFfi?.sessionId,
      sessionFfi: widget.sessionFfi,
      initialMessage: _cleanError(error),
    );
    if (saved && mounted) _refresh();
  }

  Future<void> _checkMacPermissions() async {
    final sessionFfi = widget.sessionFfi;
    if (sessionFfi == null || _checkingMac) return;
    setState(() => _checkingMac = true);
    try {
      final output = await UniLinkRemoteTerminalRunner.runShellViaSession(
        sessionFfi,
        UniLinkMacWindowMode._macPermissionCheckCommand(),
        openTimeout: const Duration(seconds: 8),
        commandTimeout: const Duration(seconds: 16),
      );
      if (!mounted) return;
      _showMacPermissionReport(output);
    } catch (e) {
      showToast(
          '${translate('Mac permission check failed')}: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _checkingMac = false);
    }
  }

  void _showMacPermissionReport(String output) {
    widget.closeDialog();
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('Mac permission check')),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isDesktop ? 620 : 0,
            maxWidth: isDesktop ? 760 : double.infinity,
            maxHeight: isDesktop ? 560 : 420,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate(
                  'Use the shown Mac user for SSH. Remote Login should be On, and the System Events test should return a number.')),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    output.trim().isEmpty
                        ? translate('No diagnostic output')
                        : output.trim(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          dialogButton('Close', onPressed: close, isOutline: true),
        ],
        onCancel: close,
      );
    });
  }
}

class _MessagePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }
}

String _cleanError(Object error) {
  final lower = error.toString().toLowerCase();
  if (lower.contains('system events') || lower.contains('not authorized')) {
    return translate('Mac accessibility permission is required');
  }
  return cleanUniLinkSshError(error);
}
