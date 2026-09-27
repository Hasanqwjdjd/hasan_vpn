import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_profile.dart';

/// SSH client + local SOCKS5 listener (ssh -D style).
/// `connect()` returns the local SOCKS5 port that SshSessionService
/// points Xray's outbound at.
class SshService {
  static SSHClient? _client;
  static SSHSocket? _socket;
  static ServerSocket? _localServer;
  static int _localPort = 0;
  static String? lastError;

  static bool get isConnected => _client != null;

  static Future<int> connect(SshProfile profile) async {
    await disconnect();
    lastError = null;

    try {
      _socket = await SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 20),
      );
    } catch (e) {
      lastError = 'SSH socket: $e';
      return 0;
    }

    final keyPem = profile.privateKey.trim();
    final SSHClient client;
    try {
      if (keyPem.isNotEmpty) {
        final ids = SSHKeyPair.fromPem(keyPem, profile.passphrase);
        client = SSHClient(
          _socket!,
          username: profile.username,
          identities: ids,
        );
      } else {
        client = SSHClient(
          _socket!,
          username: profile.username,
          onPasswordRequest: () => profile.password,
        );
      }
      await client.authenticated;
    } catch (e) {
      lastError = 'SSH auth: $e';
      try {
        await _socket?.close();
      } catch (_) {}
      _socket = null;
      return 0;
    }
    _client = client;

    try {
      _localServer = await ServerSocket.bind('127.0.0.1', 0, shared: false);
    } catch (e) {
      lastError = 'Local bind: $e';
      await disconnect();
      return 0;
    }
    _localPort = _localServer!.port;
    _localServer!.listen(_handleSocks);
    return _localPort;
  }

  static Future<bool> ping() async {
    if (_client == null || _socket == null) return false;
    return true;
  }

  static Future<void> disconnect() async {
    try {
      await _localServer?.close();
    } catch (_) {}
    _localServer = null;
    _localPort = 0;
    try {
      _client?.close();
    } catch (_) {}
    try {
      await _socket?.close();
    } catch (_) {}
    _client = null;
    _socket = null;
  }

  // ---- SOCKS5 server --------------------------------------------------

  static Future<void> _handleSocks(Socket sock) async {
    final client = _client;
    if (client == null) {
      sock.destroy();
      return;
    }

    final buf = <int>[];
    final waiters = <Completer<void>>[];
    var closed = false;
    SSHForwardChannel? channel;

    Future<Uint8List?> readN(int n) async {
      while (buf.length < n) {
        if (closed) return null;
        final c = Completer<void>();
        waiters.add(c);
        await c.future;
      }
      final out = Uint8List.fromList(buf.sublist(0, n));
      buf.removeRange(0, n);
      return out;
    }

    void flush() {
      if (waiters.isEmpty) return;
      if (buf.isNotEmpty || closed) {
        final w = waiters.removeAt(0);
        if (!w.isCompleted) w.complete();
      }
    }

    final sub = sock.listen(
      (data) {
        final ch = channel;
        if (ch == null) {
          buf.addAll(data);
          flush();
        } else {
          try {
            ch.sink.add(data);
          } catch (_) {}
        }
      },
      onDone: () {
        closed = true;
        flush();
        final ch = channel;
        if (ch != null) {
          try {
            ch.sink.close();
          } catch (_) {}
        }
      },
      onError: (_) {
        closed = true;
        flush();
        final ch = channel;
        if (ch != null) {
          try {
            ch.sink.close();
          } catch (_) {}
        }
      },
    );

    Future<void> bail() async {
      try {
        sock.destroy();
      } catch (_) {}
      try {
        await sub.cancel();
      } catch (_) {}
    }

    try {
      final hello = await readN(2);
      if (hello == null || hello[0] != 0x05) {
        await bail();
        return;
      }
      await readN(hello[1]);
      sock.add(Uint8List.fromList([0x05, 0x00]));

      final head = await readN(4);
      if (head == null || head[0] != 0x05 || head[1] != 0x01) {
        sock.add(Uint8List.fromList([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
        await bail();
        return;
      }

      final atyp = head[3];
      String host;
      if (atyp == 0x01) {
        final b = await readN(4);
        if (b == null) return await bail();
        host = '${b[0]}.${b[1]}.${b[2]}.${b[3]}';
      } else if (atyp == 0x03) {
        final l = await readN(1);
        if (l == null) return await bail();
        final name = await readN(l[0]);
        if (name == null) return await bail();
        host = String.fromCharCodes(name);
      } else if (atyp == 0x04) {
        final b = await readN(16);
        if (b == null) return await bail();
        final parts = <String>[];
        for (var i = 0; i < 16; i += 2) {
          parts.add(((b[i] << 8) | b[i + 1]).toRadixString(16));
        }
        host = parts.join(':');
      } else {
        await bail();
        return;
      }

      final pb = await readN(2);
      if (pb == null) return await bail();
      final port = (pb[0] << 8) | pb[1];

      final SSHForwardChannel ch;
      try {
        ch = await client.forwardLocal(host, port);
      } catch (_) {
        sock.add(Uint8List.fromList([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
        await bail();
        return;
      }

      channel = ch;
      sock.add(Uint8List.fromList([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));

      if (buf.isNotEmpty) {
        try {
          ch.sink.add(Uint8List.fromList(buf));
        } catch (_) {}
        buf.clear();
      }
      waiters.clear();

      ch.stream.listen(
        (d) {
          try {
            sock.add(d);
          } catch (_) {}
        },
        onDone: () {
          try {
            sock.destroy();
          } catch (_) {}
        },
        onError: (_) {
          try {
            sock.destroy();
          } catch (_) {}
        },
        cancelOnError: true,
      );
    } catch (_) {
      await bail();
    }
  }
}
