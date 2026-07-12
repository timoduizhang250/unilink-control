import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/hanako/control_client.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const kUniLinkDefaultMacHost = '192.168.137.2';
const kUniLinkLegacyMacHost = '169.254.178.183';
const kUniLinkDefaultMacUser = 'hp';
const kUniLinkDefaultMacPassword = '123456';

enum UniLinkEndpointService {
  unilink('unilink', 21118),
  smb('smb', 445),
  ssh('ssh', 22),
  rdp('rdp', 3389),
  vnc('vnc', 5900);

  final String key;
  final int port;

  const UniLinkEndpointService(this.key, this.port);
}

class UniLinkEndpointTarget {
  final String peerId;
  final String label;
  final String platform;
  final String hostname;
  final String username;
  final List<String> lanAddresses;
  final bool online;

  const UniLinkEndpointTarget({
    this.peerId = '',
    required this.label,
    required this.platform,
    required this.hostname,
    required this.username,
    required this.lanAddresses,
    this.online = false,
  });

  bool get isMac => platform.toLowerCase().contains('mac');

  UniLinkEndpointTarget copyWith({
    String? peerId,
    String? label,
    String? platform,
    String? hostname,
    String? username,
    List<String>? lanAddresses,
    bool? online,
  }) {
    return UniLinkEndpointTarget(
      peerId: peerId ?? this.peerId,
      label: label ?? this.label,
      platform: platform ?? this.platform,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      lanAddresses: lanAddresses ?? this.lanAddresses,
      online: online ?? this.online,
    );
  }
}

class UniLinkCapabilityStatus {
  final bool remoteControlAvailable;
  final String? localUniLinkHost;
  final bool smbReachable;
  final bool sshReachable;
  final bool rdpReachable;
  final bool vncReachable;
  final DateTime lastCheckedAt;

  const UniLinkCapabilityStatus({
    required this.remoteControlAvailable,
    required this.localUniLinkHost,
    required this.smbReachable,
    required this.sshReachable,
    required this.rdpReachable,
    required this.vncReachable,
    required this.lastCheckedAt,
  });
}

class UniLinkEndpointResolver {
  static const _lastHostPrefix = 'unilink-endpoint-last-host';
  static const _probeTimeout = Duration(seconds: 2);
  static const _statusTtl = Duration(seconds: 30);

  static final Map<String, UniLinkCapabilityStatus> _statusCache = {};

  static String targetKey(UniLinkEndpointTarget target) {
    final raw = [
      target.peerId,
      target.hostname,
      target.label,
    ].map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'default',
        );
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
  }

  static Future<UniLinkEndpointTarget> enrich(
    UniLinkEndpointTarget target,
  ) async {
    final peerId = target.peerId.trim();
    if (peerId.isEmpty || !hanakoControlClient.canListDevices) return target;
    try {
      final devices =
          await hanakoControlClient.listDevices().timeout(_probeTimeout);
      for (final device in devices) {
        if (device.rustdeskId.trim() != peerId) continue;
        return target.copyWith(
          label: target.label.isNotEmpty
              ? target.label
              : (device.alias ?? device.hostname),
          platform:
              target.platform.isNotEmpty ? target.platform : device.platform,
          hostname:
              target.hostname.isNotEmpty ? target.hostname : device.hostname,
          lanAddresses:
              device.lanAddresses.isNotEmpty ? device.lanAddresses : null,
        );
      }
    } catch (e) {
      debugPrint('[UniLinkEndpoint] Device enrichment skipped: $e');
    }
    return target;
  }

  static List<String> resolve(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service, {
    String? savedHost,
  }) {
    final values = <String>[
      savedHost ?? '',
      _lastHost(target, service),
      ...target.lanAddresses,
      target.hostname,
      if (target.isMac) kUniLinkDefaultMacHost,
      if (target.isMac) kUniLinkLegacyMacHost,
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final host = _cleanHost(value);
      if (host.isEmpty) continue;
      final key = host.toLowerCase();
      if (seen.add(key)) result.add(host);
    }
    return result;
  }

  static Future<String?> firstReachable(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service, {
    String? savedHost,
    Duration timeout = _probeTimeout,
  }) async {
    final enriched = await enrich(target);
    for (final host in resolve(enriched, service, savedHost: savedHost)) {
      if (await probe(host, service.port, timeout: timeout)) {
        await rememberReachableHost(enriched, service, host);
        return host;
      }
    }
    return null;
  }

  static Future<bool> probe(
    String host,
    int port, {
    Duration timeout = _probeTimeout,
  }) async {
    if (kIsWeb) return false;
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<UniLinkCapabilityStatus> capabilityStatus(
    UniLinkEndpointTarget target, {
    bool force = false,
  }) async {
    final cacheKey = targetKey(target);
    final cached = _statusCache[cacheKey];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.lastCheckedAt) < _statusTtl) {
      return cached;
    }
    final enriched = await enrich(target);
    final localUniLinkFuture = firstReachable(
      enriched,
      UniLinkEndpointService.unilink,
    );
    final smbFuture = _serviceReachable(enriched, UniLinkEndpointService.smb);
    final sshFuture = _serviceReachable(enriched, UniLinkEndpointService.ssh);
    final rdpFuture = _serviceReachable(enriched, UniLinkEndpointService.rdp);
    final vncFuture = _serviceReachable(enriched, UniLinkEndpointService.vnc);
    final result = UniLinkCapabilityStatus(
      remoteControlAvailable: enriched.peerId.trim().isNotEmpty,
      localUniLinkHost: await localUniLinkFuture,
      smbReachable: await smbFuture,
      sshReachable: await sshFuture,
      rdpReachable: await rdpFuture,
      vncReachable: await vncFuture,
      lastCheckedAt: DateTime.now(),
    );
    _statusCache[cacheKey] = result;
    return result;
  }

  static Future<void> rememberReachableHost(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service,
    String host,
  ) async {
    await bind.mainSetLocalOption(
      key: _lastHostKey(target, service),
      value: _cleanHost(host),
    );
  }

  static String perDeviceOptionKey(
    UniLinkEndpointTarget target,
    String namespace,
    String field,
  ) {
    return 'unilink-$namespace-$field-${targetKey(target)}';
  }

  static Future<bool> _serviceReachable(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service,
  ) async {
    return await firstReachable(target, service) != null;
  }

  static String _lastHost(
      UniLinkEndpointTarget target, UniLinkEndpointService service) {
    return bind.mainGetLocalOption(key: _lastHostKey(target, service)).trim();
  }

  static String _lastHostKey(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service,
  ) {
    return '$_lastHostPrefix-${service.key}-${targetKey(target)}';
  }

  static String _cleanHost(String value) {
    return value.trim().replaceAll(RegExp(r'^\\\\+'), '');
  }
}
