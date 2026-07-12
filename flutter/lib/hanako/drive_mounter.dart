import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _driveHostOption = 'unilink-drive-last-host';
const _driveShareOption = 'unilink-drive-last-share';
const _driveUserOption = 'unilink-drive-last-user';
const _drivePasswordOption = 'unilink-drive-last-password';
const _driveLetterOption = 'unilink-drive-last-letter';
const _drivePeerOption = 'unilink-drive-last-peer';
const _driveAutoMountOption = 'unilink-drive-auto-mount';

const _defaultMacDriveShare = 'UniLinkDrive';

class UniLinkDriveTarget {
  final String peerId;
  final String label;
  final String platform;
  final String hostname;
  final String username;
  final List<String> lanAddresses;

  const UniLinkDriveTarget({
    this.peerId = '',
    required this.label,
    required this.platform,
    required this.hostname,
    required this.username,
    required this.lanAddresses,
  });

  UniLinkDriveTarget copyWith({
    String? peerId,
    String? label,
    String? platform,
    String? hostname,
    String? username,
    List<String>? lanAddresses,
  }) {
    return UniLinkDriveTarget(
      peerId: peerId ?? this.peerId,
      label: label ?? this.label,
      platform: platform ?? this.platform,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      lanAddresses: lanAddresses ?? this.lanAddresses,
    );
  }

  UniLinkEndpointTarget toEndpointTarget() {
    return UniLinkEndpointTarget(
      peerId: peerId,
      label: label,
      platform: platform,
      hostname: hostname,
      username: username,
      lanAddresses: lanAddresses,
    );
  }

  factory UniLinkDriveTarget.fromEndpoint(UniLinkEndpointTarget target) {
    return UniLinkDriveTarget(
      peerId: target.peerId,
      label: target.label,
      platform: target.platform,
      hostname: target.hostname,
      username: target.username,
      lanAddresses: target.lanAddresses,
    );
  }
}

class UniLinkDriveResult {
  final bool ok;
  final String message;

  const UniLinkDriveResult(this.ok, this.message);
}

class UniLinkDriveMounter {
  static final Set<String> _autoMountingPeers = <String>{};
  static final Set<String> _autoMountFailureNotifiedPeers = <String>{};

  static Future<UniLinkDriveResult> status(String driveLetter) async {
    if (!Platform.isWindows) {
      return UniLinkDriveResult(false, translate('Windows only'));
    }
    final drive = _normalizeDriveLetter(driveLetter);
    final result = await Process.run('net', ['use', drive]);
    return UniLinkDriveResult(
      result.exitCode == 0,
      _cleanProcessText(result.stdout, result.stderr),
    );
  }

  static Future<UniLinkDriveResult> mount({
    required String driveLetter,
    required String host,
    required String share,
    required String username,
    required String password,
    bool replaceExisting = true,
  }) async {
    if (!Platform.isWindows) {
      return UniLinkDriveResult(false, translate('Windows only'));
    }
    final drive = _normalizeDriveLetter(driveLetter);
    final remote = _remotePath(host: host, share: share);
    final currentRemote = await mappedRemote(drive);
    if (currentRemote != null) {
      if (_normalizeRemote(currentRemote) != _normalizeRemote(remote)) {
        return UniLinkDriveResult(
          false,
          translate('Drive letter already in use'),
        );
      }
      if (replaceExisting) {
        await Process.run('net', ['use', drive, '/delete', '/y']);
      }
    } else if (await Directory('$drive\\').exists()) {
      return UniLinkDriveResult(
        false,
        translate('Drive letter already in use'),
      );
    } else if (replaceExisting) {
      await Process.run('net', ['use', drive, '/delete', '/y']);
    }
    final args = <String>[
      'use',
      drive,
      remote,
      password,
      if (username.trim().isNotEmpty) '/user:${username.trim()}',
      '/persistent:no',
    ];
    final result = await Process.run('net', args);
    final message = _cleanProcessText(result.stdout, result.stderr);
    return UniLinkDriveResult(result.exitCode == 0, message);
  }

  static Future<UniLinkDriveResult> unmount(String driveLetter) async {
    if (!Platform.isWindows) {
      return UniLinkDriveResult(false, translate('Windows only'));
    }
    final drive = _normalizeDriveLetter(driveLetter);
    final result = await Process.run('net', ['use', drive, '/delete', '/y']);
    final ok = result.exitCode == 0 || result.exitCode == 2;
    return UniLinkDriveResult(
        ok, _cleanProcessText(result.stdout, result.stderr));
  }

  static Future<String?> mappedRemote(String driveLetter) async {
    if (!Platform.isWindows) return null;
    final drive = _normalizeDriveLetter(driveLetter);
    final result = await Process.run('net', ['use', drive]);
    if (result.exitCode != 0) return null;
    final match =
        RegExp(r'\\\\[^\s]+\\[^\s]+').firstMatch(result.stdout.toString());
    return match?.group(0);
  }

  static Future<void> open(String driveLetter) async {
    if (!Platform.isWindows) return;
    final drive = _normalizeDriveLetter(driveLetter);
    await Process.start('explorer.exe', ['$drive\\']);
  }

  static Future<UniLinkDriveResult> autoMountAfterConnect({
    required String peerId,
    required UniLinkDriveTarget target,
  }) async {
    if (!Platform.isWindows || !_isAutoMountEnabled()) {
      return const UniLinkDriveResult(false, '');
    }

    final autoKey = peerId.trim().isNotEmpty ? peerId.trim() : target.label;
    if (_autoMountingPeers.contains(autoKey)) {
      return const UniLinkDriveResult(false, '');
    }
    _autoMountingPeers.add(autoKey);

    try {
      final resolvedEndpoint =
          await UniLinkEndpointResolver.enrich(target.toEndpointTarget());
      final resolvedTarget = UniLinkDriveTarget.fromEndpoint(resolvedEndpoint);
      if (!_shouldAutoMount(resolvedTarget)) {
        return const UniLinkDriveResult(false, '');
      }

      final driveLetter = _defaultDriveLetter(resolvedTarget);
      final share = _defaultShare(resolvedTarget);
      final username = _defaultUsername(resolvedTarget);
      final password = _defaultPassword(resolvedTarget);
      final hostCandidates = UniLinkEndpointResolver.resolve(
        resolvedEndpoint,
        UniLinkEndpointService.smb,
        savedHost: _savedLocalOption(_driveHostOption, resolvedTarget),
      );

      if (share.isEmpty || hostCandidates.isEmpty) {
        return UniLinkDriveResult(false, translate('Mount failed'));
      }

      final currentRemote = await mappedRemote(driveLetter);
      if (currentRemote != null) {
        if (_matchesAnyRemote(currentRemote, hostCandidates, share)) {
          if (await Directory('${_normalizeDriveLetter(driveLetter)}\\')
              .exists()) {
            return UniLinkDriveResult(true, translate('Mounted'));
          }
          await unmount(driveLetter);
        } else {
          final message = translate('Drive letter already in use');
          debugPrint('[UniLinkDrive] $message: $driveLetter -> $currentRemote');
          showToast(message);
          return UniLinkDriveResult(false, message);
        }
      } else if (await Directory('${_normalizeDriveLetter(driveLetter)}\\')
          .exists()) {
        final message = translate('Drive letter already in use');
        debugPrint('[UniLinkDrive] $message: $driveLetter');
        showToast(message);
        return UniLinkDriveResult(false, message);
      }

      var lastMessage = '';
      for (final host in hostCandidates) {
        final reachable = await UniLinkEndpointResolver.probe(
          host,
          UniLinkEndpointService.smb.port,
        );
        if (!reachable) continue;

        final result = await mount(
          driveLetter: driveLetter,
          host: host,
          share: share,
          username: username,
          password: password,
          replaceExisting: false,
        );
        if (result.ok) {
          await _storeDriveDefaults(
            host: host,
            share: share,
            username: username,
            password: password,
            driveLetter: driveLetter,
            target: resolvedTarget.peerId.isNotEmpty
                ? resolvedTarget
                : resolvedTarget.copyWith(peerId: peerId),
          );
          _autoMountFailureNotifiedPeers.remove(autoKey);
          showToast(translate('Remote drive mounted'));
          return result;
        }
        lastMessage = result.message;
        debugPrint('[UniLinkDrive] Mount failed on $host: ${result.message}');
      }

      final message = lastMessage.isEmpty
          ? translate('Remote SMB is not reachable')
          : lastMessage;
      debugPrint('[UniLinkDrive] Auto mount failed: $message');
      if (_autoMountFailureNotifiedPeers.add(autoKey)) {
        showToast(_driveError(message));
      }
      return UniLinkDriveResult(false, message);
    } catch (e, st) {
      debugPrint('[UniLinkDrive] Auto mount exception: $e');
      debugPrintStack(stackTrace: st);
      return UniLinkDriveResult(false, e.toString());
    } finally {
      _autoMountingPeers.remove(autoKey);
    }
  }

  static String _normalizeDriveLetter(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return 'U:';
    final letter = trimmed[0];
    return '$letter:';
  }

  static String _remotePath({required String host, required String share}) {
    final cleanHost = host.trim().replaceAll(RegExp(r'^\\\\+'), '');
    final cleanShare = share.trim().replaceAll(RegExp(r'^\\+'), '');
    return '\\\\$cleanHost\\$cleanShare';
  }
}

void showUniLinkDriveDialog({UniLinkDriveTarget? target}) {
  final hostController = TextEditingController(text: _defaultHost(target));
  final shareController = TextEditingController(text: _defaultShare(target));
  final usernameController =
      TextEditingController(text: _defaultUsername(target));
  final passwordController =
      TextEditingController(text: _defaultPassword(target));
  final driveLetterController =
      TextEditingController(text: _defaultDriveLetter(target));
  var statusMsg = '';
  var isMounted = false;
  var isInProgress = false;
  var autoMountEnabled = _isAutoMountEnabled();

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> refreshStatus() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      final result =
          await UniLinkDriveMounter.status(driveLetterController.text);
      setState(() {
        isMounted = result.ok;
        statusMsg = result.ok ? translate('Mounted') : translate('Not mounted');
        isInProgress = false;
      });
    }

    Future<void> mount() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      final result = await UniLinkDriveMounter.mount(
        driveLetter: driveLetterController.text,
        host: hostController.text,
        share: shareController.text,
        username: usernameController.text,
        password: passwordController.text,
      );
      if (result.ok) {
        await _storeDriveDefaults(
          host: hostController.text,
          share: shareController.text,
          username: usernameController.text,
          password: passwordController.text,
          driveLetter: driveLetterController.text,
          target: target,
        );
        await _storeAutoMountEnabled(autoMountEnabled);
      }
      setState(() {
        isMounted = result.ok;
        statusMsg =
            result.ok ? translate('Mounted') : _driveError(result.message);
        isInProgress = false;
      });
      if (result.ok) {
        showToast(translate('Mounted'));
        unawaited(UniLinkDriveMounter.open(driveLetterController.text));
      }
    }

    Future<void> unmount() async {
      if (isInProgress) return;
      setState(() {
        statusMsg = '';
        isInProgress = true;
      });
      final result =
          await UniLinkDriveMounter.unmount(driveLetterController.text);
      setState(() {
        isMounted = false;
        statusMsg = result.ok
            ? translate('Drive disconnected')
            : _driveError(result.message);
        isInProgress = false;
      });
      if (result.ok) showToast(translate('Drive disconnected'));
    }

    Future<void> openDrive() async {
      await UniLinkDriveMounter.open(driveLetterController.text);
    }

    if (statusMsg.isEmpty && !isInProgress) {
      unawaited(refreshStatus());
    }

    return CustomAlertDialog(
      title: Text(translate('UniLink Drive')),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isDesktop ? 420 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!Platform.isWindows)
              Text(
                translate(
                    'UniLink Drive is available on Windows in this version.'),
              )
            else ...[
              if ((target?.label ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    target!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: hostController,
                      enabled: !isInProgress,
                      decoration: InputDecoration(
                        labelText: translate('Remote host'),
                      ),
                    ).workaroundFreezeLinuxMint(),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 82,
                    child: TextField(
                      controller: driveLetterController,
                      enabled: !isInProgress,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: translate('Drive letter'),
                      ),
                    ).workaroundFreezeLinuxMint(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shareController,
                enabled: !isInProgress,
                decoration: InputDecoration(labelText: translate('Share name')),
              ).workaroundFreezeLinuxMint(),
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
                obscureText: true,
                decoration: InputDecoration(labelText: translate('Password')),
              ).workaroundFreezeLinuxMint(),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(translate('Auto mount after connection')),
                value: autoMountEnabled,
                onChanged: isInProgress
                    ? null
                    : (value) {
                        setState(() {
                          autoMountEnabled = value ?? true;
                        });
                        unawaited(_storeAutoMountEnabled(autoMountEnabled));
                      },
              ),
              if (statusMsg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    statusMsg,
                    style: TextStyle(
                      color: isMounted
                          ? const Color(0xFF0A9471)
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
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        if (Platform.isWindows)
          dialogButton('Refresh',
              onPressed: isInProgress ? null : refreshStatus),
        if (Platform.isWindows && isMounted)
          dialogButton('Open drive',
              onPressed: isInProgress ? null : openDrive),
        if (Platform.isWindows && isMounted)
          dialogButton('Disconnect drive',
              onPressed: isInProgress ? null : unmount),
        if (Platform.isWindows)
          dialogButton('Mount drive', onPressed: isInProgress ? null : mount),
      ],
      onSubmit: Platform.isWindows && !isInProgress ? mount : null,
      onCancel: close,
    );
  });
}

String _defaultHost(UniLinkDriveTarget? target) {
  final saved = _savedLocalOption(_driveHostOption, target);
  if (saved.isNotEmpty) return saved;
  final lan = target?.lanAddresses
      .where((address) => address.trim().isNotEmpty)
      .cast<String>()
      .toList();
  if (lan != null && lan.isNotEmpty) return lan.first;
  final hostname = target?.hostname.trim() ?? '';
  if (hostname.isNotEmpty) return hostname;
  final endpoint = target?.toEndpointTarget();
  if (endpoint != null) {
    final candidates =
        UniLinkEndpointResolver.resolve(endpoint, UniLinkEndpointService.smb);
    if (candidates.isNotEmpty) return candidates.first;
  }
  if (_isMacTarget(target)) {
    return kUniLinkDefaultMacHost;
  }
  return '';
}

String _defaultShare(UniLinkDriveTarget? target) {
  final saved = _savedLocalOption(_driveShareOption, target);
  if (saved.isNotEmpty) return saved;
  if (_isMacTarget(target)) {
    return _defaultMacDriveShare;
  }
  return '';
}

String _defaultUsername(UniLinkDriveTarget? target) {
  final saved = _savedLocalOption(_driveUserOption, target);
  if (saved.isNotEmpty) return saved;
  final username = target?.username.trim() ?? '';
  if (username.isNotEmpty) return username;
  if (_isMacTarget(target)) {
    return kUniLinkDefaultMacUser;
  }
  return '';
}

String _defaultPassword(UniLinkDriveTarget? target) {
  final saved = _savedEncryptedLocalOption(_drivePasswordOption, target);
  if (saved.isNotEmpty) return saved;
  if (_isMacTarget(target)) {
    return kUniLinkDefaultMacPassword;
  }
  return '';
}

String _defaultDriveLetter([UniLinkDriveTarget? target]) {
  final saved = _savedLocalOption(_driveLetterOption, target);
  if (saved.isEmpty) return 'U:';
  return UniLinkDriveMounter._normalizeDriveLetter(saved);
}

bool _isAutoMountEnabled() {
  return bind.mainGetLocalOption(key: _driveAutoMountOption) != 'N';
}

Future<void> _storeAutoMountEnabled(bool enabled) async {
  await bind.mainSetLocalOption(
    key: _driveAutoMountOption,
    value: enabled ? 'Y' : 'N',
  );
}

Future<void> _storeDriveDefaults({
  required String host,
  required String share,
  required String username,
  required String password,
  required String driveLetter,
  UniLinkDriveTarget? target,
}) async {
  final endpoint = target?.toEndpointTarget();
  await bind.mainSetLocalOption(key: _driveHostOption, value: host.trim());
  await bind.mainSetLocalOption(key: _driveShareOption, value: share.trim());
  await bind.mainSetLocalOption(key: _driveUserOption, value: username.trim());
  await bind.mainSetEncryptedLocalOption(
      key: _drivePasswordOption, value: password);
  await bind.mainSetLocalOption(
    key: _driveLetterOption,
    value: UniLinkDriveMounter._normalizeDriveLetter(driveLetter),
  );
  final storeTarget = target;
  if (endpoint != null && storeTarget != null) {
    await bind.mainSetLocalOption(
        key: _perDeviceOptionKey(_driveHostOption, storeTarget),
        value: host.trim());
    await bind.mainSetLocalOption(
        key: _perDeviceOptionKey(_driveShareOption, storeTarget),
        value: share.trim());
    await bind.mainSetLocalOption(
        key: _perDeviceOptionKey(_driveUserOption, storeTarget),
        value: username.trim());
    await bind.mainSetEncryptedLocalOption(
        key: _perDeviceOptionKey(_drivePasswordOption, storeTarget),
        value: password);
    await bind.mainSetLocalOption(
      key: _perDeviceOptionKey(_driveLetterOption, storeTarget),
      value: UniLinkDriveMounter._normalizeDriveLetter(driveLetter),
    );
    await UniLinkEndpointResolver.rememberReachableHost(
      endpoint,
      UniLinkEndpointService.smb,
      host,
    );
  }
  final peerId = target?.peerId.trim() ?? '';
  if (peerId.isNotEmpty) {
    await bind.mainSetLocalOption(key: _drivePeerOption, value: peerId);
  }
}

bool _shouldAutoMount(UniLinkDriveTarget target) {
  if (_isMacTarget(target)) return true;
  final savedPeer = bind.mainGetLocalOption(key: _drivePeerOption).trim();
  return savedPeer.isNotEmpty &&
      target.peerId.trim().isNotEmpty &&
      savedPeer == target.peerId.trim();
}

bool _matchesAnyRemote(
  String currentRemote,
  List<String> hostCandidates,
  String share,
) {
  final normalizedCurrent = _normalizeRemote(currentRemote);
  for (final host in hostCandidates) {
    final expected = UniLinkDriveMounter._remotePath(host: host, share: share);
    if (normalizedCurrent == _normalizeRemote(expected)) return true;
  }
  return false;
}

String _normalizeRemote(String value) {
  return value.trim().replaceAll('/', '\\').toLowerCase();
}

bool _isMacTarget(UniLinkDriveTarget? target) {
  return (target?.platform ?? '').toLowerCase().contains('mac');
}

String _savedLocalOption(String key, UniLinkDriveTarget? target) {
  final perDevice = _savedPerDeviceLocalOption(key, target);
  if (perDevice.isNotEmpty) return perDevice;
  if (!_canUseSavedTarget(target)) return '';
  return bind.mainGetLocalOption(key: key).trim();
}

String _savedEncryptedLocalOption(String key, UniLinkDriveTarget? target) {
  final perDevice = _savedPerDeviceEncryptedOption(key, target);
  if (perDevice.isNotEmpty) return perDevice;
  if (!_canUseSavedTarget(target)) return '';
  return bind.mainGetEncryptedLocalOption(key: key).trim();
}

String _savedPerDeviceLocalOption(String key, UniLinkDriveTarget? target) {
  if (target == null) return '';
  return bind.mainGetLocalOption(key: _perDeviceOptionKey(key, target)).trim();
}

String _savedPerDeviceEncryptedOption(String key, UniLinkDriveTarget? target) {
  if (target == null) return '';
  return bind
      .mainGetEncryptedLocalOption(key: _perDeviceOptionKey(key, target))
      .trim();
}

String _perDeviceOptionKey(String key, UniLinkDriveTarget target) {
  return UniLinkEndpointResolver.perDeviceOptionKey(
    target.toEndpointTarget(),
    'drive',
    key.replaceFirst('unilink-drive-last-', ''),
  );
}

bool _canUseSavedTarget(UniLinkDriveTarget? target) {
  final savedPeer = bind.mainGetLocalOption(key: _drivePeerOption).trim();
  final targetPeer = target?.peerId.trim() ?? '';
  return savedPeer.isEmpty || targetPeer.isEmpty || savedPeer == targetPeer;
}

String _cleanProcessText(Object stdout, Object stderr) {
  final text = '${stdout.toString()}\n${stderr.toString()}'.trim();
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _driveError(String message) {
  final text = message.trim();
  if (text.isEmpty) return translate('Mount failed');
  return '${translate('Mount failed')}: $text';
}
