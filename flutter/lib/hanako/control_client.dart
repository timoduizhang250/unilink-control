import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const _apiServerOption = 'api-server';
const _deviceIdOption = 'hanako-control-device-id';
const _deviceTokenOption = 'hanako-control-device-token';
const _lastHeartbeatAtOption = 'hanako-control-last-heartbeat-at';
const _adminTokenOption = 'hanako-control-admin-token';
const _hiddenDeviceIdsOption = 'hanako-control-hidden-device-ids';

final hanakoControlClient = HanakoControlClient();

class HanakoControlException implements Exception {
  final String message;

  const HanakoControlException(this.message);

  @override
  String toString() => 'HanakoControlException: $message';
}

class HanakoDevice {
  final String id;
  final String? alias;
  final String platform;
  final String rustdeskId;
  final String hostname;
  final List<String> lanAddresses;
  final String? lastSeenAt;
  final String? version;
  final List<String> tags;
  final String? notes;
  final String? enrolledBy;
  final String createdAt;
  final String updatedAt;

  HanakoDevice({
    required this.id,
    required this.alias,
    required this.platform,
    required this.rustdeskId,
    required this.hostname,
    required this.lanAddresses,
    required this.lastSeenAt,
    required this.version,
    required this.tags,
    required this.notes,
    required this.enrolledBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HanakoDevice.fromJson(Map<String, dynamic> json) {
    return HanakoDevice(
      id: json['id']?.toString() ?? '',
      alias: json['alias']?.toString(),
      platform: json['platform']?.toString() ?? '',
      rustdeskId: json['rustdeskId']?.toString() ?? '',
      hostname: json['hostname']?.toString() ?? '',
      lanAddresses: _stringList(json['lanAddresses']),
      lastSeenAt: json['lastSeenAt']?.toString(),
      version: json['version']?.toString(),
      tags: _stringList(json['tags']),
      notes: json['notes']?.toString(),
      enrolledBy: json['enrolledBy']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }
}

class HanakoEnrollResult {
  final HanakoDevice device;
  final String deviceToken;

  HanakoEnrollResult({required this.device, required this.deviceToken});

  factory HanakoEnrollResult.fromJson(Map<String, dynamic> json) {
    return HanakoEnrollResult(
      device: HanakoDevice.fromJson(json['device'] as Map<String, dynamic>),
      deviceToken: json['deviceToken']?.toString() ?? '',
    );
  }
}

class HanakoEnrollmentToken {
  final String id;
  final String? label;
  final String createdAt;
  final String? revokedAt;

  HanakoEnrollmentToken({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.revokedAt,
  });

  factory HanakoEnrollmentToken.fromJson(Map<String, dynamic> json) {
    return HanakoEnrollmentToken(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      revokedAt: json['revokedAt']?.toString(),
    );
  }
}

class HanakoEnrollmentTokenCreateResult {
  final String token;
  final HanakoEnrollmentToken enrollmentToken;

  HanakoEnrollmentTokenCreateResult({
    required this.token,
    required this.enrollmentToken,
  });

  factory HanakoEnrollmentTokenCreateResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return HanakoEnrollmentTokenCreateResult(
      token: json['token']?.toString() ?? '',
      enrollmentToken: HanakoEnrollmentToken.fromJson(
        json['enrollmentToken'] as Map<String, dynamic>,
      ),
    );
  }
}

class _DeviceSnapshot {
  final String rustdeskId;
  final String platform;
  final String hostname;
  final List<String> lanAddresses;
  final String version;

  _DeviceSnapshot({
    required this.rustdeskId,
    required this.platform,
    required this.hostname,
    required this.lanAddresses,
    required this.version,
  });
}

class HanakoControlClient {
  Timer? _heartbeatTimer;

  String get deviceId => bind.mainGetLocalOption(key: _deviceIdOption);
  String get deviceToken =>
      bind.mainGetEncryptedLocalOption(key: _deviceTokenOption);
  String get lastHeartbeatAt =>
      bind.mainGetLocalOption(key: _lastHeartbeatAtOption);
  String get adminToken =>
      bind.mainGetEncryptedLocalOption(key: _adminTokenOption);
  bool get isEnrolled => deviceId.isNotEmpty && deviceToken.isNotEmpty;
  bool get canListDevices => adminToken.isNotEmpty;

  Future<void> startHeartbeatLoop({
    Duration interval = const Duration(seconds: 60),
  }) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      unawaited(_heartbeatQuietly());
    });
    await _heartbeatQuietly();
  }

  void stopHeartbeatLoop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<HanakoEnrollResult> enroll({
    required String enrollmentToken,
    String? alias,
    String? enrolledBy,
  }) async {
    final apiUri = await _apiUri('/api/enroll');
    final snapshot = await _collectDeviceSnapshot();
    final response = await http.post(
      apiUri,
      headers: _jsonHeaders(),
      body: jsonEncode({
        'enrollmentToken': enrollmentToken.trim(),
        'rustdeskId': snapshot.rustdeskId,
        'platform': snapshot.platform,
        'hostname': snapshot.hostname,
        'alias': alias?.trim(),
        'lanAddresses': snapshot.lanAddresses,
        'version': snapshot.version,
        'enrolledBy': enrolledBy?.trim(),
      }),
    );
    final payload = _decodeResponse(response);
    final result = HanakoEnrollResult.fromJson(payload);
    if (result.device.id.isEmpty || result.deviceToken.isEmpty) {
      throw const HanakoControlException('Enrollment response is incomplete');
    }
    await _storeEnrollment(result.device.id, result.deviceToken);
    return result;
  }

  Future<HanakoDevice?> heartbeat() async {
    if (!isEnrolled) {
      return null;
    }
    final apiUri = await _apiUri('/api/devices/heartbeat');
    final snapshot = await _collectDeviceSnapshot();
    final response = await http.post(
      apiUri,
      headers: _jsonHeaders(deviceToken: deviceToken),
      body: jsonEncode({
        'deviceId': deviceId,
        'rustdeskId': snapshot.rustdeskId,
        'platform': snapshot.platform,
        'hostname': snapshot.hostname,
        'lanAddresses': snapshot.lanAddresses,
        'version': snapshot.version,
      }),
    );
    final device = HanakoDevice.fromJson(_decodeResponse(response));
    await bind.mainSetLocalOption(
      key: _lastHeartbeatAtOption,
      value: DateTime.now().toUtc().toIso8601String(),
    );
    return device;
  }

  Future<List<HanakoDevice>> listDevices() async {
    if (!canListDevices) {
      throw const HanakoControlException('Admin token is not configured');
    }
    final apiUri = await _apiUri('/api/devices');
    final response = await http.get(
      apiUri,
      headers: {
        'X-Admin-Token': adminToken,
      },
    );
    final payload = _decodeListResponse(response);
    final hidden = _hiddenDeviceKeys();
    return payload
        .map(HanakoDevice.fromJson)
        .where((device) => !_isHiddenDevice(device, hidden))
        .toList();
  }

  Future<HanakoEnrollmentTokenCreateResult> createEnrollmentToken({
    String? label,
  }) async {
    if (!canListDevices) {
      throw const HanakoControlException('Admin token is not configured');
    }
    final apiUri = await _apiUri('/api/enrollment-tokens');
    final response = await http.post(
      apiUri,
      headers: {
        'Content-Type': 'application/json',
        'X-Admin-Token': adminToken,
      },
      body: jsonEncode({
        'label': label?.trim(),
      }),
    );
    final result = HanakoEnrollmentTokenCreateResult.fromJson(
      _decodeResponse(response),
    );
    if (result.token.isEmpty || result.enrollmentToken.id.isEmpty) {
      throw const HanakoControlException(
        'Enrollment token response is incomplete',
      );
    }
    return result;
  }

  Future<HanakoDevice> updateDevice({
    required String id,
    String? alias,
    List<String>? tags,
    String? notes,
  }) async {
    if (!canListDevices) {
      throw const HanakoControlException('Admin token is not configured');
    }
    final apiUri = await _apiUri('/api/devices/$id');
    final payload = <String, dynamic>{};
    if (alias != null) payload['alias'] = alias.trim();
    if (tags != null) payload['tags'] = tags;
    if (notes != null) payload['notes'] = notes.trim();
    final response = await http.patch(
      apiUri,
      headers: {
        'Content-Type': 'application/json',
        'X-Admin-Token': adminToken,
      },
      body: jsonEncode(payload),
    );
    return HanakoDevice.fromJson(_decodeResponse(response));
  }

  Future<HanakoDevice> deleteDevice({required String id}) async {
    if (!canListDevices) {
      throw const HanakoControlException('Admin token is not configured');
    }
    final apiUri = await _apiUri('/api/devices/$id');
    final response = await http.delete(
      apiUri,
      headers: {
        'X-Admin-Token': adminToken,
      },
    );
    return HanakoDevice.fromJson(_decodeResponse(response));
  }

  Future<void> hideDeviceLocally({
    required String id,
    String rustdeskId = '',
  }) async {
    final hidden = _hiddenDeviceKeys();
    final cleanId = id.trim();
    final cleanRustdeskId = rustdeskId.trim();
    if (cleanId.isNotEmpty) hidden.add(cleanId);
    if (cleanRustdeskId.isNotEmpty) hidden.add(cleanRustdeskId);
    await bind.mainSetLocalOption(
      key: _hiddenDeviceIdsOption,
      value: jsonEncode(hidden.toList()..sort()),
    );
  }

  Future<void> clearEnrollment() async {
    await bind.mainSetLocalOption(key: _deviceIdOption, value: '');
    await bind.mainSetEncryptedLocalOption(key: _deviceTokenOption, value: '');
    await bind.mainSetLocalOption(key: _lastHeartbeatAtOption, value: '');
  }

  Future<void> setAdminToken(String token) async {
    await bind.mainSetEncryptedLocalOption(
      key: _adminTokenOption,
      value: token.trim(),
    );
  }

  Set<String> _hiddenDeviceKeys() {
    final raw = bind.mainGetLocalOption(key: _hiddenDeviceIdsOption).trim();
    if (raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet();
      }
    } catch (e) {
      debugPrint('UniLink hidden device list ignored: $e');
    }
    return <String>{};
  }

  bool _isHiddenDevice(HanakoDevice device, Set<String> hidden) {
    return hidden.contains(device.id.trim()) ||
        hidden.contains(device.rustdeskId.trim());
  }

  Future<void> _heartbeatQuietly() async {
    try {
      await heartbeat();
    } catch (e) {
      debugPrint('UniLink Control heartbeat skipped: $e');
    }
  }

  Future<void> _storeEnrollment(String id, String token) async {
    await bind.mainSetLocalOption(key: _deviceIdOption, value: id);
    await bind.mainSetEncryptedLocalOption(
      key: _deviceTokenOption,
      value: token,
    );
  }

  Future<Uri> _apiUri(String path) async {
    final base = (await bind.mainGetOption(key: _apiServerOption)).trim();
    if (base.isEmpty) {
      throw const HanakoControlException('api-server is not configured');
    }
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized$path');
  }

  Future<_DeviceSnapshot> _collectDeviceSnapshot() async {
    final rustdeskId = (await bind.mainGetMyId()).trim();
    if (rustdeskId.isEmpty) {
      throw const HanakoControlException('Device ID is not ready');
    }

    final version = await _clientVersion();
    return _DeviceSnapshot(
      rustdeskId: rustdeskId,
      platform: _platformName(),
      hostname: await _hostname(),
      lanAddresses: await _lanAddresses(),
      version: version,
    );
  }

  Future<String> _clientVersion() async {
    try {
      return (await bind.mainGetVersion()).trim();
    } catch (_) {
      return '';
    }
  }

  String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  Future<String> _hostname() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isWindows) {
        return (await deviceInfo.windowsInfo).computerName;
      }
      if (Platform.isMacOS) {
        return (await deviceInfo.macOsInfo).computerName;
      }
      if (Platform.isLinux) {
        return (await deviceInfo.linuxInfo).name;
      }
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand}-${androidInfo.model}';
      }
      if (Platform.isIOS) {
        return (await deviceInfo.iosInfo).utsname.machine;
      }
    } catch (e) {
      debugPrint('UniLink Control hostname fallback: $e');
    }
    return Platform.localHostname;
  }

  Future<List<String>> _lanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      ).timeout(const Duration(seconds: 2));
      final addresses = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            addresses.add(address.address);
          }
        }
      }
      return addresses.toList()..sort();
    } catch (e) {
      debugPrint('UniLink Control LAN address lookup skipped: $e');
      return const [];
    }
  }

  Map<String, String> _jsonHeaders({String? deviceToken}) {
    final headers = {'Content-Type': 'application/json'};
    if (deviceToken != null && deviceToken.isNotEmpty) {
      headers['X-Device-Token'] = deviceToken;
    }
    return headers;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HanakoControlException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const HanakoControlException('Expected a JSON object response');
    }
    return decoded;
  }

  List<Map<String, dynamic>> _decodeListResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HanakoControlException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const HanakoControlException('Expected a JSON list response');
    }
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const HanakoControlException(
          'Expected every list item to be a JSON object',
        );
      }
      return item;
    }).toList();
  }
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList();
}
