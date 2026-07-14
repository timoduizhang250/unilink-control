import 'package:flutter_hbb/hanako/connection_health.dart';
import 'package:flutter_hbb/hanako/public_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UniLink server lines', () {
    test('official line uses WebSocket and HITOHA remains unavailable', () {
      expect(uniLinkOfficialServerLine.useWebSocket, isTrue);
      expect(uniLinkOfficialServerLine.isAvailable, isTrue);
      expect(uniLinkHitohaServerLine.isAvailable, isFalse);
      expect(uniLinkHitohaServerLine.unavailableReason, isNotEmpty);
    });
  });

  group('official line login policy', () {
    bool requiresLogin({
      String appName = 'UniLink Control',
      String peerId = '123456789',
      String idServer = '',
      String relayServer = '',
      String apiServer = '',
      String key = '',
      String accessToken = '',
    }) {
      return uniLinkShouldRequireOfficialLogin(
        appName: appName,
        peerId: peerId,
        idServer: idServer,
        relayServer: relayServer,
        apiServer: apiServer,
        key: key,
        accessToken: accessToken,
      );
    }

    test('requires login for a normal device ID on the official line', () {
      expect(requiresLogin(), isTrue);
    });

    test('requires login for an explicitly public device ID', () {
      expect(
        requiresLogin(
          peerId: '123456789@public',
          idServer: 'custom.example.com',
        ),
        isTrue,
      );
    });

    test('does not block LAN addresses or a custom line', () {
      expect(requiresLogin(peerId: '192.168.1.10'), isFalse);
      expect(requiresLogin(peerId: 'mac.local'), isFalse);
      expect(
        requiresLogin(idServer: 'custom.example.com', key: 'custom-key'),
        isFalse,
      );
    });

    test('does not prompt with a token or in a non-UniLink build', () {
      expect(requiresLogin(accessToken: 'token'), isFalse);
      expect(requiresLogin(appName: 'RustDesk'), isFalse);
    });
  });

  group('connection health guidance', () {
    test('parses milliseconds, seconds, and numeric delays', () {
      expect(uniLinkDelayMilliseconds('347 ms'), 347);
      expect(uniLinkDelayMilliseconds('0.33s'), 330);
      expect(uniLinkDelayMilliseconds('288'), 288);
      expect(uniLinkDelayMilliseconds('unknown'), isNull);
    });

    test('shows high latency guidance only at the threshold', () {
      expect(
        uniLinkHighLatencyHint(rawDelay: '249ms', direct: false),
        isNull,
      );
      expect(
        uniLinkHighLatencyHint(rawDelay: '250ms', direct: false),
        contains('公网中继'),
      );
      expect(
        uniLinkHighLatencyHint(rawDelay: '300ms', direct: true),
        contains('300ms'),
      );
    });

    test('describes direct and relay routes', () {
      expect(uniLinkConnectionRouteHint(true), contains('设备直连'));
      expect(uniLinkConnectionRouteHint(false), contains('公网中继'));
      expect(uniLinkConnectionRouteHint(null), isNull);
    });
  });
}
