import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/terminal_model.dart';

class UniLinkRemoteTerminalRunner {
  static int _nextTerminalId = 90000;
  static final Map<String, Future<void>> _sessionQueues = {};

  static Future<String> runShellViaSession(
    FFI sourceFfi,
    String command, {
    Duration openTimeout = const Duration(seconds: 12),
    Duration commandTimeout = const Duration(seconds: 18),
    int retries = 1,
    Duration retryDelay = const Duration(milliseconds: 450),
  }) async {
    return _enqueue(sourceFfi.sessionId.toString(), () async {
      Object? lastError;
      for (var attempt = 0; attempt <= retries; attempt++) {
        try {
          return await _runShellViaSessionOnce(
            sourceFfi,
            command,
            openTimeout: openTimeout,
            commandTimeout: commandTimeout,
          );
        } catch (e) {
          lastError = e;
          if (attempt >= retries) break;
          debugPrint(
              '[UniLinkRemoteTerminalRunner] command failed, retrying: $e');
          await Future<void>.delayed(retryDelay);
        }
      }
      throw lastError ?? Exception(translate('Remote command failed'));
    });
  }

  static Future<T> _enqueue<T>(
    String key,
    Future<T> Function() task,
  ) async {
    final previous = _sessionQueues[key] ?? Future<void>.value();
    final completer = Completer<void>();
    final current = completer.future;
    _sessionQueues[key] = current;
    try {
      await previous.catchError((_) {});
      return await task();
    } finally {
      if (!completer.isCompleted) completer.complete();
      if (identical(_sessionQueues[key], current)) {
        _sessionQueues.remove(key);
      }
    }
  }

  static Future<String> _runShellViaSessionOnce(
    FFI sourceFfi,
    String command, {
    required Duration openTimeout,
    required Duration commandTimeout,
  }) async {
    final connToken =
        bind.sessionGetConnToken(sessionId: sourceFfi.sessionId) ?? '';
    if (connToken.trim().isEmpty) {
      throw Exception(translate('Remote session token is not available'));
    }

    final terminalId = _nextTerminalId++;
    final marker =
        'UNILINK_CMD_${DateTime.now().microsecondsSinceEpoch}_$terminalId';
    final opened = Completer<void>();
    final completed = Completer<_TerminalCommandResult>();
    final output = StringBuffer();

    late final FFI ffi;
    late final TerminalModel model;

    void tryComplete() {
      if (completed.isCompleted) return;
      final text = _stripAnsi(output.toString());
      final endPattern = RegExp('${RegExp.escape(marker)}:END:(\\d+)');
      final end = endPattern.firstMatch(text);
      if (end == null) return;
      final beginNeedle = '$marker:BEGIN';
      final begin = text.lastIndexOf(beginNeedle, end.start);
      if (begin < 0) return;
      final rawBody = text.substring(begin + beginNeedle.length, end.start);
      completed.complete(_TerminalCommandResult(
        rawBody.replaceAll('\r', '').trim(),
        int.tryParse(end.group(1) ?? '') ?? 1,
      ));
    }

    ffi = FFI(null);
    model = TerminalModel(
      ffi,
      terminalId: terminalId,
      headless: true,
      onHeadlessOpened: () {
        if (!opened.isCompleted) opened.complete();
      },
      onHeadlessData: (text) {
        output.write(text);
        tryComplete();
      },
      onHeadlessClosed: (exitCode) {
        if (!completed.isCompleted) {
          completed.completeError(
              Exception('Remote terminal closed with exit code $exitCode'));
        }
      },
      onHeadlessError: (message) {
        if (!completed.isCompleted) {
          completed.completeError(Exception(message));
        }
      },
    );
    ffi.registerTerminalModel(terminalId, model);

    try {
      ffi.start(
        sourceFfi.id,
        isTerminal: true,
        connToken: connToken,
      );
      await opened.future.timeout(openTimeout);
      await bind.sessionSendTerminalInput(
        sessionId: ffi.sessionId,
        terminalId: terminalId,
        data: '${_wrapCommand(command, marker)}\r',
      );
      final result = await completed.future.timeout(commandTimeout);
      if (result.exitCode != 0) {
        throw Exception(result.output.isEmpty
            ? 'Remote command failed with exit code ${result.exitCode}'
            : result.output);
      }
      return result.output;
    } finally {
      try {
        await model.closeTerminal();
      } catch (e) {
        debugPrint('[UniLinkRemoteTerminalRunner] close terminal failed: $e');
      }
      ffi.unregisterTerminalModel(terminalId);
      model.dispose();
      await ffi.close();
    }
  }

  static String _wrapCommand(String command, String marker) {
    return "printf '\\n$marker:BEGIN\\n'; "
        "{ $command ; }; "
        "code=\$?; "
        "printf '\\n$marker:END:%s\\n' \"\$code\"";
  }

  static String _stripAnsi(String value) {
    return value.replaceAll(
      RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])'),
      '',
    );
  }
}

class _TerminalCommandResult {
  final String output;
  final int exitCode;

  const _TerminalCommandResult(this.output, this.exitCode);
}
