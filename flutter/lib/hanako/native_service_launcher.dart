import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/hanako/endpoint_resolver.dart';
import 'package:url_launcher/url_launcher.dart';

class UniLinkNativeServiceLauncher {
  static Future<bool> launch(
    UniLinkEndpointTarget target,
    UniLinkEndpointService service,
  ) async {
    if (kIsWeb) return false;
    final host = await UniLinkEndpointResolver.firstReachable(target, service);
    if (host == null) return false;
    if (service == UniLinkEndpointService.rdp && Platform.isWindows) {
      await Process.start(
          'mstsc.exe', ['/v:' + host + ':' + service.port.toString()]);
      return true;
    }
    if (service == UniLinkEndpointService.vnc && Platform.isWindows) {
      final tigerVncPaths = <String>[
        r'C:\Program Files\TigerVNC\vncviewer.exe',
        r'C:\Program Files (x86)\TigerVNC\vncviewer.exe',
      ];
      for (final viewerPath in tigerVncPaths) {
        if (!File(viewerPath).existsSync()) continue;
        await Process.start(
          viewerPath,
          [host + '::' + service.port.toString()],
        );
        return true;
      }
    }
    final scheme = service == UniLinkEndpointService.rdp ? 'rdp' : 'vnc';
    return launchUrl(
      Uri.parse(scheme + '://' + host + ':' + service.port.toString()),
      mode: LaunchMode.externalApplication,
    );
  }
}
