import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UniLinkAndroidUpdateResult {
  final bool installerLaunched;
  final bool permissionRequired;

  const UniLinkAndroidUpdateResult({
    required this.installerLaunched,
    required this.permissionRequired,
  });
}

class UniLinkAndroidUpdater {
  static const _channel = MethodChannel('mChannel');
  static final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A stale cache file must not prevent a fresh update attempt.
    }
  }

  static Future<UniLinkAndroidUpdateResult> downloadAndInstall({
    required String downloadUrl,
    required String expectedSha256,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('更新下载地址无效');
    }
    final expected = expectedSha256.trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(expected)) {
      throw const FormatException('更新清单缺少有效的安装包校验值');
    }

    final client = http.Client();
    File? partialApk;
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载安装包失败（${response.statusCode}）');
      }

      final cacheDir = await getTemporaryDirectory();
      final updateDir = Directory('${cacheDir.path}/unilink-updates');
      await updateDir.create(recursive: true);
      partialApk = File('${updateDir.path}/unilink-control-update.apk.part');
      final apk = File('${updateDir.path}/unilink-control-update.apk');
      await _deleteIfExists(partialApk);
      await _deleteIfExists(apk);

      final sink = partialApk.openWrite();
      var received = 0;
      final total = response.contentLength ?? 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }

      final actual =
          (await sha256.bind(partialApk.openRead()).first).toString();
      if (actual != expected) {
        await _deleteIfExists(partialApk);
        throw const FormatException('安装包校验失败，请稍后重试');
      }
      await partialApk.rename(apk.path);
      partialApk = null;
      onProgress?.call(1);

      final status = await _channel.invokeMethod<String>(
        'install_android_update',
        apk.path,
      );
      return UniLinkAndroidUpdateResult(
        installerLaunched: status == 'launched',
        permissionRequired: status == 'permission_required',
      );
    } finally {
      client.close();
      if (partialApk != null) {
        await _deleteIfExists(partialApk);
      }
    }
  }
}
