int? uniLinkDelayMilliseconds(String? rawDelay) {
  if (rawDelay == null) return null;
  final normalized = rawDelay.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  final milliseconds = RegExp(r'(\d+(?:\.\d+)?)\s*ms').firstMatch(normalized);
  if (milliseconds != null) {
    return double.tryParse(milliseconds.group(1)!)?.round();
  }

  final seconds = RegExp(r'(\d+(?:\.\d+)?)\s*s').firstMatch(normalized);
  if (seconds != null) {
    final value = double.tryParse(seconds.group(1)!);
    return value == null ? null : (value * 1000).round();
  }

  return double.tryParse(normalized)?.round();
}

String? uniLinkHighLatencyHint({
  required String? rawDelay,
  required bool? direct,
  int thresholdMilliseconds = 250,
}) {
  final delay = uniLinkDelayMilliseconds(rawDelay);
  if (delay == null || delay < thresholdMilliseconds) return null;
  if (direct == false) {
    return '当前使用公网中继，延迟约 ${delay}ms；在同一 Wi-Fi 下会优先直连。';
  }
  return '当前网络延迟约 ${delay}ms，请检查两台设备的网络。';
}

String? uniLinkConnectionRouteHint(bool? direct) {
  if (direct == null) return null;
  return direct ? '已建立设备直连' : '已通过公网中继连接';
}
