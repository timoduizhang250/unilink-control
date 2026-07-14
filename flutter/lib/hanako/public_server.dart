const String uniLinkPublicServerName = 'public';

class UniLinkServerLine {
  final String id;
  final String name;
  final String region;
  final String description;
  final String idServer;
  final String relayServer;
  final String apiServer;
  final String key;
  final bool isOfficial;
  final bool isFreeThirdParty;
  final bool useWebSocket;
  final bool isAvailable;
  final String unavailableReason;

  const UniLinkServerLine({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.idServer,
    required this.relayServer,
    required this.apiServer,
    required this.key,
    this.isOfficial = false,
    this.isFreeThirdParty = false,
    this.useWebSocket = false,
    this.isAvailable = true,
    this.unavailableReason = '',
  });

  bool matches({
    required String idServer,
    required String relayServer,
    required String apiServer,
    required String key,
  }) {
    return _normalize(idServer) == _normalize(this.idServer) &&
        _normalize(relayServer) == _normalize(this.relayServer) &&
        _normalize(apiServer) == _normalize(this.apiServer) &&
        key.trim() == this.key.trim();
  }
}

const uniLinkOfficialServerLine = UniLinkServerLine(
  id: 'official',
  name: '官方公共线路',
  region: '默认',
  description: '官方公共网络，控制其他设备前需要登录；网络距离较远时延迟可能较高。',
  idServer: '',
  relayServer: '',
  apiServer: '',
  key: '',
  isOfficial: true,
  useWebSocket: true,
);

const uniLinkHitohaServerLine = UniLinkServerLine(
  id: 'hitoha-sg',
  name: 'HITOHA 免费线路',
  region: '新加坡',
  description: '当前协议不兼容且存在丢包，暂时不能用于设备连接。',
  idServer: '103.131.188.71',
  relayServer: '103.131.188.71',
  apiServer: '',
  key: 'xMnueFSYC65LbBsCOGJKj29N0fU8ZEPJ0NqZZiARbW0=',
  isFreeThirdParty: true,
  isAvailable: false,
  unavailableReason: '协议不兼容，等待替换为已验证的亚洲线路',
);

const uniLinkBuiltInServerLines = <UniLinkServerLine>[
  uniLinkOfficialServerLine,
  uniLinkHitohaServerLine,
];

const uniLinkCustomServerLineId = 'custom';

String uniLinkDetectServerLineId({
  required String idServer,
  required String relayServer,
  required String apiServer,
  required String key,
}) {
  for (final line in uniLinkBuiltInServerLines) {
    if (line.matches(
      idServer: idServer,
      relayServer: relayServer,
      apiServer: apiServer,
      key: key,
    )) {
      return line.id;
    }
  }
  return uniLinkCustomServerLineId;
}

String uniLinkPublicPeerId(String peerId) {
  final normalized = peerId.trim().replaceAll(' ', '');
  if (normalized.isEmpty) return normalized;
  if (normalized.contains('@') ||
      normalized.contains('?') ||
      _looksLikeDirectAddress(normalized)) {
    return normalized;
  }

  var relaySuffix = '';
  var base = normalized;
  if (base.endsWith(r'\r') || base.endsWith('/r')) {
    relaySuffix = base.substring(base.length - 2);
    base = base.substring(0, base.length - 2);
  }

  if (base.isEmpty ||
      base.contains('@') ||
      base.contains('?') ||
      _looksLikeDirectAddress(base)) {
    return normalized;
  }
  return '$base$relaySuffix@$uniLinkPublicServerName';
}

bool uniLinkCanUsePublicServer(String peerId) {
  final normalized = peerId.trim().replaceAll(' ', '');
  if (normalized.isEmpty) return false;
  if (normalized.endsWith('@$uniLinkPublicServerName')) return true;
  if (normalized.contains('@') ||
      normalized.contains('?') ||
      _looksLikeDirectAddress(normalized)) {
    return false;
  }
  var base = normalized;
  if (base.endsWith(r'\r') || base.endsWith('/r')) {
    base = base.substring(0, base.length - 2);
  }
  return base.isNotEmpty && !_looksLikeDirectAddress(base);
}

bool uniLinkShouldRequireOfficialLogin({
  required String appName,
  required String peerId,
  required String idServer,
  required String relayServer,
  required String apiServer,
  required String key,
  required String accessToken,
}) {
  if (!appName.toLowerCase().contains('unilink') ||
      accessToken.trim().isNotEmpty) {
    return false;
  }

  final normalizedPeer = peerId.trim().replaceAll(' ', '');
  if (!uniLinkCanUsePublicServer(normalizedPeer)) return false;

  final explicitlyOfficial =
      normalizedPeer.endsWith('@$uniLinkPublicServerName');
  final currentLine = uniLinkDetectServerLineId(
    idServer: idServer,
    relayServer: relayServer,
    apiServer: apiServer,
    key: key,
  );
  return explicitlyOfficial || currentLine == uniLinkOfficialServerLine.id;
}

bool _looksLikeDirectAddress(String value) {
  final id = value.split('/').first;
  if (id.contains(':')) return true;
  if (_ipv4Regex.hasMatch(id)) return true;
  return id.contains('.');
}

final _ipv4Regex = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

String _normalize(String value) {
  var result = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
