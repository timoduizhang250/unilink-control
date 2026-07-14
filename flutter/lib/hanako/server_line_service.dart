import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/hanako/public_server.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class UniLinkServerLineApplyResult {
  final bool applied;
  final bool ready;
  final String message;

  const UniLinkServerLineApplyResult({
    required this.applied,
    required this.ready,
    required this.message,
  });
}

class _ServerLineSnapshot {
  final ServerConfig config;
  final String directServer;
  final String allowWebSocket;
  final String localIpAddress;
  final String accessToken;
  final String userInfo;

  const _ServerLineSnapshot({
    required this.config,
    required this.directServer,
    required this.allowWebSocket,
    required this.localIpAddress,
    required this.accessToken,
    required this.userInfo,
  });
}

Future<UniLinkServerLineApplyResult> applyUniLinkServerLine(
  UniLinkServerLine line, {
  Duration readyTimeout = const Duration(seconds: 8),
}) async {
  if (!line.isAvailable) {
    return UniLinkServerLineApplyResult(
      applied: false,
      ready: false,
      message:
          line.unavailableReason.isEmpty ? '该线路暂不可用' : line.unavailableReason,
    );
  }

  final previous = _captureServerLineSnapshot();
  try {
    await bind.mainSetOption(
      key: kOptionAllowWebSocket,
      value: line.useWebSocket ? 'Y' : 'N',
    );
    final applied = await setServerConfig(
      null,
      null,
      ServerConfig(
        idServer: line.idServer,
        relayServer: line.relayServer,
        apiServer: line.apiServer,
        key: line.key,
      ),
    );
    if (!applied) {
      await _restoreServerLineSnapshot(previous);
      return const UniLinkServerLineApplyResult(
        applied: false,
        ready: false,
        message: '线路配置未能保存',
      );
    }

    await bind.mainSetOption(key: kOptionDirectServer, value: 'N');
    await bind.mainSetOption(key: 'local-ip-addr', value: '');

    final ready = await _waitForServerReady(readyTimeout);
    if (!ready) {
      await _restoreServerLineSnapshot(previous);
      return const UniLinkServerLineApplyResult(
        applied: false,
        ready: false,
        message: '新线路未能接入，已恢复原线路',
      );
    }
    return UniLinkServerLineApplyResult(
      applied: true,
      ready: true,
      message: '已接入 ${line.name}',
    );
  } catch (error) {
    await _restoreServerLineSnapshot(previous);
    return UniLinkServerLineApplyResult(
      applied: false,
      ready: false,
      message: '线路切换失败，已恢复原线路：$error',
    );
  }
}

_ServerLineSnapshot _captureServerLineSnapshot() {
  return _ServerLineSnapshot(
    config: ServerConfig(
      idServer: bind.mainGetOptionSync(key: 'custom-rendezvous-server'),
      relayServer: bind.mainGetOptionSync(key: 'relay-server'),
      apiServer: bind.mainGetOptionSync(key: 'api-server'),
      key: bind.mainGetOptionSync(key: 'key'),
    ),
    directServer: bind.mainGetOptionSync(key: kOptionDirectServer),
    allowWebSocket: bind.mainGetOptionSync(key: kOptionAllowWebSocket),
    localIpAddress: bind.mainGetOptionSync(key: 'local-ip-addr'),
    accessToken: bind.mainGetLocalOption(key: 'access_token'),
    userInfo: bind.mainGetLocalOption(key: 'user_info'),
  );
}

Future<void> _restoreServerLineSnapshot(_ServerLineSnapshot snapshot) async {
  await bind.mainSetOption(
    key: kOptionAllowWebSocket,
    value: snapshot.allowWebSocket,
  );
  await setServerConfig(null, null, snapshot.config);
  await bind.mainSetOption(
    key: kOptionDirectServer,
    value: snapshot.directServer,
  );
  await bind.mainSetOption(
    key: 'local-ip-addr',
    value: snapshot.localIpAddress,
  );
  await bind.mainSetLocalOption(
    key: 'access_token',
    value: snapshot.accessToken,
  );
  await bind.mainSetLocalOption(key: 'user_info', value: snapshot.userInfo);
  gFFI.userModel.refreshCurrentUser();
}

Future<bool> _waitForServerReady(Duration timeout) async {
  await Future<void>.delayed(const Duration(milliseconds: 750));
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final status =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      if (status['status_num'] == 1) return true;
    } catch (_) {
      // Keep polling while the mediator restarts.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}
