import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:flutter_hbb/hanako/ssh_terminal.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RemoteSelectionDownloadResult {
  final bool ok;
  final String message;
  final Directory? directory;
  final List<String> localPaths;

  const RemoteSelectionDownloadResult({
    required this.ok,
    required this.message,
    this.directory,
    this.localPaths = const [],
  });
}

class UniLinkRemoteSelectionDownloader {
  static bool _running = false;

  static Future<RemoteSelectionDownloadResult> downloadFinderSelection(
      UniLinkEndpointTarget target,
      {FFI? sessionFfi}) async {
    if (_running) {
      return RemoteSelectionDownloadResult(
        ok: false,
        message: translate('Remote selection download is already running'),
      );
    }
    _running = true;
    UniLinkSshConnection? connection;
    try {
      if (!Platform.isWindows) {
        return RemoteSelectionDownloadResult(
          ok: false,
          message: translate('Windows only'),
        );
      }
      if (!target.isMac) {
        return RemoteSelectionDownloadResult(
          ok: false,
          message: translate('Remote selection download supports Mac only'),
        );
      }
      connection = await UniLinkSshProfiles.connect(
        target,
        sessionId: sessionFfi?.sessionId,
        sessionFfi: sessionFfi,
      );
      final selectedPaths = await _selectedFinderPaths(connection.client);
      if (selectedPaths.isEmpty) {
        return RemoteSelectionDownloadResult(
          ok: false,
          message: translate('Select files in Finder first'),
        );
      }
      final sftp = await connection.client.sftp();
      final root = await _downloadRoot(target);
      final sessionDir = await _uniqueDirectory(
        root,
        _safeName(_targetTitle(target)),
      );
      await sessionDir.create(recursive: true);
      final localPaths = <String>[];
      for (final remotePath in selectedPaths) {
        final downloaded = await _downloadPath(
          sftp,
          remotePath,
          Directory(sessionDir.path),
        );
        localPaths.addAll(downloaded);
      }
      if (localPaths.isEmpty) {
        return RemoteSelectionDownloadResult(
          ok: false,
          directory: sessionDir,
          message: translate('No downloadable files were selected'),
        );
      }
      unawaited(_openDirectory(sessionDir));
      return RemoteSelectionDownloadResult(
        ok: true,
        directory: sessionDir,
        localPaths: localPaths,
        message: translate('Remote selection downloaded').replaceAll(
          '{}',
          selectedPaths.length.toString(),
        ),
      );
    } catch (e) {
      return RemoteSelectionDownloadResult(
        ok: false,
        message:
            '${translate('Remote selection download failed')}: ${_cleanError(e)}',
      );
    } finally {
      connection?.close();
      _running = false;
    }
  }

  static Future<List<String>> _selectedFinderPaths(SSHClient client) async {
    const script = r'''
set output to ""
tell application "Finder"
    set selectedItems to selection
    repeat with selectedItem in selectedItems
        set output to output & POSIX path of (selectedItem as alias) & linefeed
    end repeat
end tell
return output
''';
    final command = "osascript -e ${_shellQuote(script)}";
    final bytes = await client.run(command).timeout(const Duration(seconds: 8));
    return utf8
        .decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.startsWith('/'))
        .toList(growable: false);
  }

  static Future<Directory> _downloadRoot(UniLinkEndpointTarget target) async {
    final downloads = await getDownloadsDirectory();
    final base = downloads ??
        Directory(p.join(
          Platform.environment['USERPROFILE'] ?? Directory.current.path,
          'Downloads',
        ));
    return Directory(p.join(
      base.path,
      'UniLink Control',
      _safeName(_targetTitle(target)),
    ));
  }

  static Future<Directory> _uniqueDirectory(
    Directory parent,
    String prefix,
  ) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .replaceAll('T', '_');
    var candidate = Directory(p.join(parent.path, '${prefix}_$stamp'));
    var index = 2;
    while (await candidate.exists()) {
      candidate = Directory(p.join(parent.path, '${prefix}_${stamp}_$index'));
      index += 1;
    }
    return candidate;
  }

  static Future<List<String>> _downloadPath(
    SftpClient sftp,
    String remotePath,
    Directory localParent,
  ) async {
    // Do not follow remote symbolic links. A Finder selection can contain a
    // link to its ancestor, which otherwise creates unbounded recursive SFTP
    // traversal and falsely reports a completed download.
    final attrs = await sftp.stat(remotePath, followLink: false);
    final name = _safeName(_basename(remotePath));
    if (attrs.isDirectory) {
      final dir = Directory(p.join(localParent.path, name));
      await dir.create(recursive: true);
      final entries = await sftp.listdir(remotePath);
      for (final entry in entries) {
        if (entry.filename == '.' || entry.filename == '..') continue;
        await _downloadPath(
          sftp,
          _joinRemote(remotePath, entry.filename),
          dir,
        );
      }
      return [dir.path];
    }
    if (!attrs.isFile) {
      return const [];
    }
    final target = await _uniqueFile(localParent, name);
    final sink = target.openWrite();
    try {
      await sftp.download(
        remotePath,
        sink,
        length: attrs.size,
        closeDestination: true,
      );
    } catch (_) {
      await sink.close();
      rethrow;
    }
    return [target.path];
  }

  static Future<File> _uniqueFile(Directory parent, String name) async {
    final parsed = p.basename(name).trim().isEmpty ? 'remote-file' : name;
    final ext = p.extension(parsed);
    final stem =
        ext.isEmpty ? parsed : parsed.substring(0, parsed.length - ext.length);
    var candidate = File(p.join(parent.path, parsed));
    var index = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(parent.path, '${stem}_$index$ext'));
      index += 1;
    }
    return candidate;
  }

  static Future<void> _openDirectory(Directory directory) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [directory.path]);
    }
  }

  static String _targetTitle(UniLinkEndpointTarget target) {
    return [
      target.label,
      target.hostname,
      target.peerId,
    ].map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'Mac',
        );
  }

  static String _basename(String remotePath) {
    final normalized = remotePath.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final index = trimmed.lastIndexOf('/');
    return index >= 0 ? trimmed.substring(index + 1) : trimmed;
  }

  static String _joinRemote(String parent, String child) {
    final cleanParent =
        parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent;
    return '$cleanParent/$child';
  }

  static String _safeName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? 'Device' : cleaned;
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
    if (lower.contains('osascript')) {
      return translate('Finder selection is not available');
    }
    return text.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
  }
}
