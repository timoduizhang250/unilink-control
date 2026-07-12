import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:path/path.dart' as p;

class RemoteDropUploadResult {
  final bool ok;
  final String message;
  final String remoteDirectory;
  final int uploadedCount;

  const RemoteDropUploadResult({
    required this.ok,
    required this.message,
    this.remoteDirectory = '',
    this.uploadedCount = 0,
  });
}

class UniLinkRemoteDropUploader {
  static bool _running = false;

  static Future<RemoteDropUploadResult> uploadToMac(
      UniLinkEndpointTarget target, List<String> localPaths,
      {FFI? sessionFfi}) async {
    if (_running) {
      return RemoteDropUploadResult(
        ok: false,
        message: translate('Remote upload is already running'),
      );
    }
    _running = true;
    UniLinkSshConnection? connection;
    try {
      if (!Platform.isWindows) {
        return RemoteDropUploadResult(
          ok: false,
          message: translate('Windows only'),
        );
      }
      if (!target.isMac) {
        return RemoteDropUploadResult(
          ok: false,
          message: translate('Remote drop upload supports Mac only'),
        );
      }
      final validPaths = await _validLocalPaths(localPaths);
      if (validPaths.isEmpty) {
        return RemoteDropUploadResult(
          ok: false,
          message: translate('No valid files to upload'),
        );
      }

      connection = await UniLinkSshProfiles.connect(
        target,
        sessionId: sessionFfi?.sessionId,
        sessionFfi: sessionFfi,
      );
      final remoteDirectory =
          await _finderDropDirectory(connection.client).timeout(
        const Duration(seconds: 8),
        onTimeout: () => _remoteDownloadsDirectory(connection!.client),
      );
      final sftp = await connection.client.sftp();
      await _ensureDirectory(sftp, remoteDirectory);

      var uploadedCount = 0;
      for (final localPath in validPaths) {
        uploadedCount += await _uploadPath(sftp, localPath, remoteDirectory);
      }
      return RemoteDropUploadResult(
        ok: true,
        remoteDirectory: remoteDirectory,
        uploadedCount: uploadedCount,
        message:
            '${translate('Uploaded files to Mac').replaceAll('{}', uploadedCount.toString())}: $remoteDirectory',
      );
    } catch (e) {
      return RemoteDropUploadResult(
        ok: false,
        message: '${translate('Remote drop upload failed')}: ${_cleanError(e)}',
      );
    } finally {
      connection?.close();
      _running = false;
    }
  }

  static Future<List<String>> _validLocalPaths(List<String> paths) async {
    final result = <String>[];
    final seen = <String>{};
    for (final path in paths) {
      final clean = path.trim();
      if (clean.isEmpty || !seen.add(clean.toLowerCase())) continue;
      final type = await FileSystemEntity.type(clean);
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.directory) {
        result.add(clean);
      }
    }
    return result;
  }

  static Future<String> _finderDropDirectory(SSHClient client) async {
    const script = r'''
try
    tell application "Finder"
        return POSIX path of (insertion location as alias)
    end tell
on error
    return POSIX path of (path to downloads folder)
end try
''';
    final bytes = await client.run("osascript -e ${_shellQuote(script)}");
    final value = utf8.decode(bytes, allowMalformed: true).trim();
    if (value.startsWith('/')) return _stripTrailingSlash(value);
    return _remoteDownloadsDirectory(client);
  }

  static Future<String> _remoteDownloadsDirectory(SSHClient client) async {
    final bytes = await client.run(r'printf %s "$HOME/Downloads"');
    final value = utf8.decode(bytes, allowMalformed: true).trim();
    return value.startsWith('/') ? value : '/tmp';
  }

  static Future<int> _uploadPath(
    SftpClient sftp,
    String localPath,
    String remoteParent,
  ) async {
    final type = await FileSystemEntity.type(localPath, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      final remoteDir = await _uniqueRemotePath(
        sftp,
        remoteParent,
        _safeRemoteName(p.basename(localPath)),
      );
      await _ensureDirectory(sftp, remoteDir);
      var count = 0;
      await for (final entity
          in Directory(localPath).list(recursive: false, followLinks: false)) {
        count += await _uploadPath(sftp, entity.path, remoteDir);
      }
      return count;
    }
    if (type != FileSystemEntityType.file) return 0;
    final remoteFile = await _uniqueRemotePath(
      sftp,
      remoteParent,
      _safeRemoteName(p.basename(localPath)),
    );
    final file = await sftp.open(
      remoteFile,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      final writer = file.write(_readFileChunks(File(localPath)));
      await writer.done;
    } finally {
      await file.close();
    }
    return 1;
  }

  static Stream<Uint8List> _readFileChunks(File file) {
    return file.openRead().map(
          (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        );
  }

  static Future<void> _ensureDirectory(SftpClient sftp, String path) async {
    if (await _remoteExists(sftp, path)) return;
    final parent = _remoteParent(path);
    if (parent != path && parent.isNotEmpty) {
      await _ensureDirectory(sftp, parent);
    }
    try {
      await sftp.mkdir(path);
    } catch (_) {
      if (!await _remoteExists(sftp, path)) rethrow;
    }
  }

  static Future<String> _uniqueRemotePath(
    SftpClient sftp,
    String parent,
    String name,
  ) async {
    final cleanName = name.trim().isEmpty ? 'upload' : name.trim();
    final ext = p.extension(cleanName);
    final stem = ext.isEmpty
        ? cleanName
        : cleanName.substring(0, cleanName.length - ext.length);
    var candidate = _joinRemote(parent, cleanName);
    var index = 2;
    while (await _remoteExists(sftp, candidate)) {
      candidate = _joinRemote(parent, '${stem}_$index$ext');
      index += 1;
    }
    return candidate;
  }

  static Future<bool> _remoteExists(SftpClient sftp, String path) async {
    try {
      await sftp.stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _remoteParent(String path) {
    final clean = _stripTrailingSlash(path);
    final index = clean.lastIndexOf('/');
    if (index <= 0) return '/';
    return clean.substring(0, index);
  }

  static String _joinRemote(String parent, String child) {
    final cleanParent = _stripTrailingSlash(parent);
    return '$cleanParent/$child';
  }

  static String _stripTrailingSlash(String value) {
    var result = value.trim();
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _safeRemoteName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[/:\x00-\x1F]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? 'upload' : cleaned;
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _cleanError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('auth')) {
      return translate('SSH authentication failed');
    }
    if (lower.contains('host key')) {
      return translate('SSH host key changed');
    }
    if (lower.contains('socket') || lower.contains('timed out')) {
      return translate('SSH is not reachable');
    }
    return text.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
  }
}
