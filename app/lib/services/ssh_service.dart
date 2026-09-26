import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/ssh_profile.dart';

/// مدیریت اتصال SSH + فوروارد لوکال به SOCKS5 روی سرور SSH.
class SshService {
  SshService._();

  static SSHClient? _client;
  static SSHSocket? _socket;
  static SSHForwardChannel? _forward;
  static int _localPort = 0;
  static String? _lastError;

  static bool get isConnected => _client != null && _forward != null;
  static int get localSocksPort => _localPort;
  static String? get lastError => _lastError;

  /// اتصال به SSH و باز کردن یک پورت لوکال که به SOCKS5 روی سرور SSH
  /// (پیش‌فرض 127.0.0.1:1080) فوروارد می‌کند. پورت محلی برگردانده می‌شود.
  static Future<int> connect(SshProfile profile) async {
    _lastError = null;
    await disconnect();

    if (!profile.isComplete) {
      _lastError = 'SSH profile is incomplete (host/user + password or key)';
      return 0;
    }

    try {
      // 1) اتصال سوکت به سرور SSH
      final socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 20),
      );
      _socket = socket;

      // 2) کلاینت SSH با رمز یا کلید
      final identities = profile.privateKey.trim().isNotEmpty
          ? SSHKeyPair.fromPem(profile.privateKey,
              profile.passphrase.isEmpty ? null : profile.passphrase)
          : null;

      final client = SSHClient(
        socket,
        username: profile.username,
        identities: identities,
        onPasswordRequest: () => profile.password,
      );
      _client = client;

      // 3) انتظار برای احراز هویت
      await client.authenticated;

      // 4) فوروارد لوکال → SOCKS5 روی سرور SSH
      //    forwardLocal(host, port) روی سرور SSH یک اتصال TCP به host:port
      //    باز می‌کند و روی یک پورت لوکال در اپ گوش می‌دهد.
      final forward = await client.forwardLocal(
        '127.0.0.1',
        profile.remoteSocksPort,
      );
      _forward = forward;
      _localPort = forward.localPort;

      return _localPort;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('SSH connect error: $e');
      await disconnect();
      return 0;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _forward?.close();
    } catch (_) {}
    _forward = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _localPort = 0;
  }

  static Future<bool> ping() async {
    if (_client == null) return false;
    try {
      // dartssh2 2.11: session.stdout یک Stream<List<int>> است و مستقیم
      // await نمی‌شه؛ با listen جمعش می‌کنیم.
      final session = await _client!.run('echo ok');
      final chunks = <int>[];
      final completer = Completer<void>();
      final sub = session.stdout.listen(
        (data) => chunks.addAll(data),
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          sub.cancel();
        },
      );
      await sub.cancel();
      final out = String.fromCharCodes(chunks);
      return out.trim().contains('ok');
    } catch (_) {
      return false;
    }
  }
}
