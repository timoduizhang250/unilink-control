import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/remote_terminal_runner.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:xterm/xterm.dart';

const _sshHostOption = 'host';
const _sshPortOption = 'port';
const _sshUserOption = 'user';
const _sshPasswordOption = 'password';
const _sshHostKeyOption = 'host-key';

class SshProfile {
  final String peerId;
  final String host;
  final int port;
  final String username;
  final String password;
  final String hostKeyFingerprint;

  const SshProfile({
    required this.peerId,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.hostKeyFingerprint,
  });

  SshProfile copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? hostKeyFingerprint,
  }) {
    return SshProfile(
      peerId: peerId,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
    );
  }
}

class UniLinkSshConnection {
  final UniLinkEndpointTarget target;
  final SshProfile profile;
  final SSHClient client;

  const UniLinkSshConnection({
    required this.target,
    required this.profile,
    required this.client,
  });

  void close() {
    client.close();
  }
}

class UniLinkSshProfiles {
  static Future<SshProfile> load(UniLinkEndpointTarget target) async {
    return loadWithSession(target);
  }

  static Future<SshProfile> loadWithSession(
    UniLinkEndpointTarget target, {
    SessionID? sessionId,
    FFI? sessionFfi,
  }) async {
    final enriched = await UniLinkEndpointResolver.enrich(target);
    final savedHost = _localOption(enriched, _sshHostOption);
    final candidates =
        UniLinkEndpointResolver.resolve(enriched, UniLinkEndpointService.ssh);
    final host = await UniLinkEndpointResolver.firstReachable(
          enriched,
          UniLinkEndpointService.ssh,
          savedHost: savedHost,
        ) ??
        savedHost.ifNotEmpty() ??
        (candidates.isNotEmpty ? candidates.first : '');
    if (host.isEmpty) {
      throw Exception(translate('Remote host is not available'));
    }
    final port = int.tryParse(_localOption(enriched, _sshPortOption)) ??
        UniLinkEndpointService.ssh.port;
    final remoteUsername = await _remoteSessionUsername(sessionFfi);
    final username = remoteUsername.ifNotEmpty() ??
        _localOption(enriched, _sshUserOption).ifNotEmpty() ??
        enriched.username.ifNotEmpty() ??
        (enriched.isMac ? kUniLinkDefaultMacUser : '');
    final savedPassword = _encryptedOption(enriched, _sshPasswordOption);
    final sessionPassword = await _sessionOsPassword(sessionId);
    final password = savedPassword.ifNotEmpty() ??
        sessionPassword.ifNotEmpty() ??
        (enriched.isMac ? kUniLinkDefaultMacPassword : '');
    final fingerprint = _encryptedOption(enriched, _sshHostKeyOption);
    return SshProfile(
      peerId: enriched.peerId,
      host: host,
      port: port,
      username: username,
      password: password,
      hostKeyFingerprint: fingerprint,
    );
  }

  static Future<void> store(
    UniLinkEndpointTarget target,
    SshProfile profile,
  ) async {
    final enriched = await UniLinkEndpointResolver.enrich(target);
    await bind.mainSetLocalOption(
        key: _optionKey(enriched, _sshHostOption), value: profile.host);
    await bind.mainSetLocalOption(
        key: _optionKey(enriched, _sshPortOption),
        value: profile.port.toString());
    await bind.mainSetLocalOption(
        key: _optionKey(enriched, _sshUserOption), value: profile.username);
    await bind.mainSetEncryptedLocalOption(
        key: _optionKey(enriched, _sshPasswordOption), value: profile.password);
    await bind.mainSetEncryptedLocalOption(
        key: _optionKey(enriched, _sshHostKeyOption),
        value: profile.hostKeyFingerprint);
    await UniLinkEndpointResolver.rememberReachableHost(
      enriched,
      UniLinkEndpointService.ssh,
      profile.host,
    );
  }

  static Future<UniLinkSshConnection> connect(
    UniLinkEndpointTarget target, {
    SessionID? sessionId,
    FFI? sessionFfi,
    SshProfile? profileOverride,
    Duration socketTimeout = const Duration(seconds: 8),
    Duration handshakeTimeout = const Duration(seconds: 15),
    Duration authTimeout = const Duration(seconds: 15),
  }) async {
    final enriched = await UniLinkEndpointResolver.enrich(target);
    final profile = profileOverride ??
        await loadWithSession(
          enriched,
          sessionId: sessionId,
          sessionFfi: sessionFfi,
        );
    final hosts = profileOverride == null
        ? _orderedHostCandidates(enriched, profile.host)
        : <String>[profile.host];
    Object? lastError;
    for (final host in hosts.take(4)) {
      final trial = profile.copyWith(
        host: host,
        hostKeyFingerprint:
            host == profile.host ? profile.hostKeyFingerprint : '',
      );
      try {
        return await _connectProfile(
          enriched,
          trial,
          socketTimeout: socketTimeout,
          handshakeTimeout: handshakeTimeout,
          authTimeout: authTimeout,
        );
      } catch (e) {
        lastError = e;
        debugPrint('[UniLinkSshProfiles] SSH failed for $host: $e');
      }
    }
    throw lastError ?? Exception(translate('SSH connection failed'));
  }

  static Future<UniLinkSshConnection> _connectProfile(
    UniLinkEndpointTarget enriched,
    SshProfile profile, {
    required Duration socketTimeout,
    required Duration handshakeTimeout,
    required Duration authTimeout,
  }) async {
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: socketTimeout,
    );

    String seenFingerprint = '';
    final client = SSHClient(
      socket,
      username: profile.username,
      onPasswordRequest: () => profile.password,
      onUserInfoRequest: (request) {
        if (profile.password.isEmpty) return null;
        return List<String>.filled(request.prompts.length, profile.password);
      },
      handshakeTimeout: handshakeTimeout,
      authTimeout: authTimeout,
      onVerifyHostKey: (type, fingerprint) {
        final text = utf8.decode(fingerprint, allowMalformed: true);
        seenFingerprint = '$type $text';
        final saved = profile.hostKeyFingerprint.trim();
        return saved.isEmpty || saved == seenFingerprint;
      },
    );
    try {
      await client.authenticated.timeout(handshakeTimeout + authTimeout);
    } catch (_) {
      client.close();
      rethrow;
    }
    await store(
      enriched,
      profile.copyWith(hostKeyFingerprint: seenFingerprint),
    );
    return UniLinkSshConnection(
      target: enriched,
      profile: profile.copyWith(hostKeyFingerprint: seenFingerprint),
      client: client,
    );
  }

  static List<String> _orderedHostCandidates(
    UniLinkEndpointTarget target,
    String firstHost,
  ) {
    final savedHost = _localOption(target, _sshHostOption);
    final values = <String>[
      firstHost,
      ...UniLinkEndpointResolver.resolve(
        target,
        UniLinkEndpointService.ssh,
        savedHost: savedHost,
      ),
    ];
    final seen = <String>{};
    return values.where((host) {
      final clean = host.trim();
      if (clean.isEmpty) return false;
      return seen.add(clean.toLowerCase());
    }).toList(growable: false);
  }

  static String _localOption(UniLinkEndpointTarget target, String field) {
    return bind.mainGetLocalOption(key: _optionKey(target, field)).trim();
  }

  static String _encryptedOption(UniLinkEndpointTarget target, String field) {
    return bind
        .mainGetEncryptedLocalOption(key: _optionKey(target, field))
        .trim();
  }

  static String _optionKey(UniLinkEndpointTarget target, String field) {
    return UniLinkEndpointResolver.perDeviceOptionKey(target, 'ssh', field);
  }

  static Future<String> _sessionOsPassword(SessionID? sessionId) async {
    if (sessionId == null) return '';
    try {
      return (await bind.sessionGetOption(
                sessionId: sessionId,
                arg: 'os-password',
              ) ??
              '')
          .trim();
    } catch (e) {
      debugPrint('[UniLinkSshProfiles] OS password import skipped: $e');
      return '';
    }
  }

  static Future<String> _remoteSessionUsername(FFI? sessionFfi) async {
    if (sessionFfi == null) return '';
    try {
      final text = await UniLinkRemoteTerminalRunner.runShellViaSession(
        sessionFfi,
        'id -un 2>/dev/null || whoami',
        openTimeout: const Duration(seconds: 5),
        commandTimeout: const Duration(seconds: 6),
      );
      return text
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    } catch (e) {
      debugPrint('[UniLinkSshProfiles] Remote username detection skipped: $e');
      return '';
    }
  }
}

Future<bool> showUniLinkSshProfileDialog({
  required UniLinkEndpointTarget target,
  SessionID? sessionId,
  FFI? sessionFfi,
  String initialMessage = '',
}) async {
  final initialProfile = await _loadEditableProfile(
    target,
    sessionId: sessionId,
    sessionFfi: sessionFfi,
  );
  final hostController = TextEditingController(text: initialProfile.host);
  final portController =
      TextEditingController(text: initialProfile.port.toString());
  final usernameController =
      TextEditingController(text: initialProfile.username);
  final passwordController =
      TextEditingController(text: initialProfile.password);
  var statusMsg = initialMessage.trim();
  var isInProgress = false;
  var obscurePassword = true;

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    Future<void> saveAndTest() async {
      if (isInProgress) return;
      final host = hostController.text.trim();
      final port = int.tryParse(portController.text.trim());
      final username = usernameController.text.trim();
      final password = passwordController.text;
      if (host.isEmpty) {
        setState(() => statusMsg = translate('Remote host is not available'));
        return;
      }
      if (port == null || port <= 0 || port > 65535) {
        setState(() => statusMsg = translate('Invalid SSH port'));
        return;
      }
      if (username.isEmpty) {
        setState(() => statusMsg = translate('Username is required'));
        return;
      }

      final profile = initialProfile.copyWith(
        host: host,
        port: port,
        username: username,
        password: password,
        hostKeyFingerprint: host == initialProfile.host
            ? initialProfile.hostKeyFingerprint
            : '',
      );

      setState(() {
        statusMsg = translate('Testing SSH...');
        isInProgress = true;
      });

      UniLinkSshConnection? connection;
      try {
        await UniLinkSshProfiles.store(target, profile);
        connection = await UniLinkSshProfiles.connect(
          target,
          sessionId: sessionId,
          sessionFfi: sessionFfi,
          profileOverride: profile,
          socketTimeout: const Duration(seconds: 5),
          handshakeTimeout: const Duration(seconds: 10),
          authTimeout: const Duration(seconds: 10),
        );
        await connection.client
            .run(r'printf unilink-ok')
            .timeout(const Duration(seconds: 8));
        showToast(translate('SSH login saved'));
        close(true);
      } catch (e) {
        await UniLinkSshProfiles.store(target, initialProfile);
        setState(() {
          statusMsg = sshLoginFailureMessage(e, profile);
          isInProgress = false;
        });
      } finally {
        connection?.close();
      }
    }

    return CustomAlertDialog(
      title: Text(translate('SSH Login')),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isDesktop ? 420 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate(
                  'Enter the Mac login password once. UniLink will save it and use SSH automatically next time.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: hostController,
                    enabled: !isInProgress,
                    autofocus: true,
                    decoration:
                        InputDecoration(labelText: translate('Remote Host')),
                  ).workaroundFreezeLinuxMint(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: portController,
                    enabled: !isInProgress,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration:
                        InputDecoration(labelText: translate('Remote Port')),
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: usernameController,
              enabled: !isInProgress,
              decoration: InputDecoration(labelText: translate('Username')),
            ).workaroundFreezeLinuxMint(),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              enabled: !isInProgress,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: translate('Password'),
                suffixIcon: IconButton(
                  onPressed: isInProgress
                      ? null
                      : () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ).workaroundFreezeLinuxMint(),
            if (statusMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  statusMsg,
                  style: TextStyle(
                    color: statusMsg == translate('Testing SSH...')
                        ? Theme.of(context).textTheme.bodyMedium?.color
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (isInProgress)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel',
            onPressed: isInProgress ? null : close, isOutline: true),
        dialogButton('Save and test',
            onPressed: isInProgress ? null : () => unawaited(saveAndTest())),
      ],
      onSubmit: isInProgress ? null : () => unawaited(saveAndTest()),
      onCancel: isInProgress ? null : close,
    );
  });
  return res == true;
}

Future<SshProfile> _loadEditableProfile(
  UniLinkEndpointTarget target, {
  SessionID? sessionId,
  FFI? sessionFfi,
}) async {
  try {
    return await UniLinkSshProfiles.loadWithSession(
      target,
      sessionId: sessionId,
      sessionFfi: sessionFfi,
    );
  } catch (_) {
    final enriched = await UniLinkEndpointResolver.enrich(target);
    final candidates =
        UniLinkEndpointResolver.resolve(enriched, UniLinkEndpointService.ssh);
    return SshProfile(
      peerId: enriched.peerId,
      host: candidates.isNotEmpty ? candidates.first : enriched.hostname,
      port: UniLinkEndpointService.ssh.port,
      username: enriched.username.ifNotEmpty() ??
          (enriched.isMac ? kUniLinkDefaultMacUser : ''),
      password: enriched.isMac ? kUniLinkDefaultMacPassword : '',
      hostKeyFingerprint: '',
    );
  }
}

class UniLinkSshActionButton extends StatefulWidget {
  final UniLinkEndpointTarget target;
  final double iconSize;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? beforeOpen;

  const UniLinkSshActionButton({
    Key? key,
    required this.target,
    this.iconSize = 19,
    this.padding,
    this.beforeOpen,
  }) : super(key: key);

  @override
  State<UniLinkSshActionButton> createState() => _UniLinkSshActionButtonState();
}

class _UniLinkSshActionButtonState extends State<UniLinkSshActionButton> {
  late Future<UniLinkCapabilityStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = UniLinkEndpointResolver.capabilityStatus(widget.target);
  }

  @override
  void didUpdateWidget(covariant UniLinkSshActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (UniLinkEndpointResolver.targetKey(oldWidget.target) !=
        UniLinkEndpointResolver.targetKey(widget.target)) {
      _statusFuture = UniLinkEndpointResolver.capabilityStatus(widget.target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UniLinkCapabilityStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final checking = snapshot.connectionState == ConnectionState.waiting;
        final reachable = snapshot.data?.sshReachable == true;
        final message = checking
            ? translate('Checking SSH...')
            : reachable
                ? translate('SSH')
                : translate('SSH is not reachable');
        return Tooltip(
          message: message,
          child: IconButton(
            padding: widget.padding,
            icon: Icon(
              checking ? Icons.hourglass_empty_rounded : Icons.terminal_rounded,
              size: widget.iconSize,
            ),
            onPressed: reachable
                ? () {
                    widget.beforeOpen?.call();
                    showUniLinkSshTerminal(target: widget.target);
                  }
                : null,
          ),
        );
      },
    );
  }
}

void showUniLinkSshTerminal({required UniLinkEndpointTarget target}) {
  gFFI.dialogManager.show((setState, close, context) {
    final title = _targetTitle(target);
    return CustomAlertDialog(
      title: Text('${translate('SSH')} - $title'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: isDesktop ? 720 : 0,
          maxWidth: isDesktop ? 900 : double.infinity,
          minHeight: isDesktop ? 460 : 0,
          maxHeight: isDesktop ? 620 : double.infinity,
        ),
        child: SizedBox(
          width: isDesktop ? 820 : double.infinity,
          height: isDesktop ? 520 : 420,
          child: SshTerminalPage(target: target),
        ),
      ),
      actions: [
        dialogButton('Close', onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

class SshTerminalPage extends StatefulWidget {
  final UniLinkEndpointTarget target;

  const SshTerminalPage({Key? key, required this.target}) : super(key: key);

  @override
  State<SshTerminalPage> createState() => _SshTerminalPageState();
}

class _SshTerminalPageState extends State<SshTerminalPage> {
  static const _defaultPadding =
      EdgeInsets.symmetric(horizontal: 5, vertical: 2);

  late final SshTerminalModel _model;
  final _focusNode = FocusNode(canRequestFocus: true);
  double? _cellHeight;

  @override
  void initState() {
    super.initState();
    _model = SshTerminalModel(widget.target);
    _model.onResizeExternal = (w, h, pw, ph) {
      _cellHeight = ph.toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      unawaited(_model.connect());
    });
  }

  @override
  void dispose() {
    _model.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  EdgeInsets _padding(double heightPx) {
    final cellHeight = _cellHeight;
    if (cellHeight == null || cellHeight <= 0 || heightPx <= 0) {
      return _defaultPadding;
    }
    final rows = (heightPx / cellHeight).floor();
    if (rows <= 0) return _defaultPadding;
    final extra = heightPx - rows * cellHeight;
    return EdgeInsets.symmetric(
      horizontal: _defaultPadding.horizontal / 2,
      vertical: extra / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return TerminalView(
              _model.terminal,
              controller: _model.terminalController,
              focusNode: _focusNode,
              backgroundOpacity: 0.7,
              padding: _padding(constraints.maxHeight),
              onSecondaryTapDown: (details, offset) async {
                final selection = _model.terminalController.selection;
                if (selection != null) {
                  final text = _model.terminal.buffer.getText(selection);
                  _model.terminalController.clearSelection();
                  await Clipboard.setData(ClipboardData(text: text));
                } else {
                  final data = await Clipboard.getData('text/plain');
                  final text = data?.text;
                  if (text != null) _model.terminal.paste(text);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class SshTerminalModel with ChangeNotifier {
  final UniLinkEndpointTarget target;
  late final Terminal terminal;
  late final TerminalController terminalController;
  void Function(int w, int h, int pw, int ph)? onResizeExternal;

  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _disposed = false;
  bool _connecting = false;

  SshTerminalModel(this.target) {
    terminal = Terminal(maxLines: 10000);
    terminalController = TerminalController();
    terminal.onOutput = _handleInput;
    terminal.onResize = _handleResize;
  }

  Future<void> connect() async {
    if (_connecting || _session != null) return;
    _connecting = true;
    try {
      final profile = await UniLinkSshProfiles.load(target);
      _writeSystem(
          '${translate('Connecting to SSH')} ${profile.username}@${profile.host}:${profile.port} ...');

      final connection = await UniLinkSshProfiles.connect(target);
      final client = connection.client;
      _client = client;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
          height: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
        ),
      );
      if (_disposed) {
        session.close();
        client.close();
        return;
      }
      _session = session;
      _writeSystem(translate('SSH connected'));
      _stdoutSub = session.stdout.listen(_writeBytes);
      _stderrSub = session.stderr.listen(_writeBytes);
      unawaited(session.done.whenComplete(() {
        if (!_disposed) _writeSystem(translate('SSH disconnected'));
      }));
    } catch (e) {
      _writeSystem(
          '${translate('SSH connection failed')}: ${cleanUniLinkSshError(e)}');
    } finally {
      _connecting = false;
    }
  }

  void _handleInput(String data) {
    final session = _session;
    if (session == null) return;
    if ((isMobile || (isWeb && !isWebDesktop)) && data == '\n') {
      data = '\r';
    }
    session.write(Uint8List.fromList(utf8.encode(data)));
  }

  void _handleResize(int w, int h, int pw, int ph) {
    if (w <= 0 || h <= 0 || pw <= 0 || ph <= 0) return;
    onResizeExternal?.call(w, h, pw, ph);
    _session?.resizeTerminal(w, h, pw, ph);
  }

  void _writeBytes(Uint8List bytes) {
    if (_disposed) return;
    terminal.write(utf8.decode(bytes, allowMalformed: true));
  }

  void _writeSystem(String text) {
    if (_disposed) return;
    terminal.write('\r\n$text\r\n');
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    _session?.close();
    _client?.close();
    super.dispose();
  }
}

extension _StringExt on String {
  String? ifNotEmpty() {
    final value = trim();
    return value.isEmpty ? null : value;
  }
}

String _targetTitle(UniLinkEndpointTarget target) {
  return [
    target.label,
    target.hostname,
    target.peerId,
  ].map((value) => value.trim()).firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => 'Device',
      );
}

bool isUniLinkSshAuthenticationError(Object error) {
  return error.toString().toLowerCase().contains('auth');
}

String cleanUniLinkSshError(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('host key')) {
    return translate('SSH host key changed');
  }
  if (isUniLinkSshAuthenticationError(error)) {
    return translate('SSH authentication failed');
  }
  if (lower.contains('socket') || lower.contains('timed out')) {
    return translate('SSH is not reachable');
  }
  return text.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
}

String sshLoginFailureMessage(Object error, SshProfile profile) {
  final message = cleanUniLinkSshError(error);
  if (!isUniLinkSshAuthenticationError(error)) return message;
  return '$message\n'
      '${translate('Tried SSH user')}: ${profile.username}@${profile.host}:${profile.port}\n'
      '${translate('Check the Mac short username, Mac login password, and Remote Login permission.')}';
}
