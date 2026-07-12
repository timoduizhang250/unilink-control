import 'dart:io';

import 'package:flutter/services.dart';

class UniLinkWindowsFileDrag {
  static const _channel = MethodChannel('org.rustdesk.rustdesk/host');

  static Future<bool> dragFiles(List<String> paths) async {
    if (!Platform.isWindows || paths.isEmpty) return false;
    final existing = <String>[];
    for (final path in paths) {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        existing.add(path);
      }
    }
    if (existing.isEmpty) return false;
    final result = await _channel.invokeMethod<bool>('dragFiles', existing);
    return result == true;
  }
}
