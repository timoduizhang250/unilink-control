import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/hanako/public_server.dart';
import 'package:flutter_hbb/models/platform_model.dart';

Future<bool> ensureUniLinkOfficialLogin(String peerId) async {
  final required = uniLinkShouldRequireOfficialLogin(
    appName: bind.mainGetAppNameSync(),
    peerId: peerId,
    idServer: bind.mainGetOptionSync(key: 'custom-rendezvous-server'),
    relayServer: bind.mainGetOptionSync(key: 'relay-server'),
    apiServer: bind.mainGetOptionSync(key: 'api-server'),
    key: bind.mainGetOptionSync(key: 'key'),
    accessToken: bind.mainGetLocalOption(key: 'access_token'),
  );
  if (!required) return true;

  final result = await loginDialog();
  final loggedIn = result == true &&
      bind.mainGetLocalOption(key: 'access_token').trim().isNotEmpty;
  if (!loggedIn) {
    showToast('使用官方线路控制设备前，请先登录 UniLink 账号');
  }
  return loggedIn;
}

Future<void> uniLinkConnect(
  BuildContext context,
  String peerId, {
  bool isFileTransfer = false,
  bool isViewCamera = false,
  bool isTerminal = false,
  bool isTcpTunneling = false,
  bool isRDP = false,
  bool forceRelay = false,
  String? password,
  String? connToken,
  bool? isSharedPassword,
}) async {
  if (!await ensureUniLinkOfficialLogin(peerId)) return;
  await connect(
    context,
    peerId,
    isFileTransfer: isFileTransfer,
    isViewCamera: isViewCamera,
    isTerminal: isTerminal,
    isTcpTunneling: isTcpTunneling,
    isRDP: isRDP,
    forceRelay: forceRelay,
    password: password,
    connToken: connToken,
    isSharedPassword: isSharedPassword,
  );
}
