import 'package:flutter/foundation.dart';

import '../models/ssh_profile.dart';

/// ⚠️ TEMPORARY STUB
///
/// پیاده‌سازی واقعی SSH tunnel با dartssh2 در نسخه‌های اخیر API متفاوتی
/// دارد و نیاز به بررسی دقیق مستندات dartssh2 2.11 دارد. برای اینکه CI
/// سبز بماند، این سرویس فعلاً stub است: connect() بلافاصله با خطا برمی‌گردد
/// و UI به کاربر پیام می‌دهد.
///
/// برای پیاده‌سازی واقعی: dartssh2 2.11 از `SSHForwardChannel` با
/// `forwardLocal` استفاده می‌کند و کاربر باید خودش `ServerSocket` بسازد
/// و ترافیک را به forward pipe کند (شبیه `ssh -D`).
class SshService {
  SshService._();

  static bool _connected = false;
  static int _localPort = 0;
  static String? _lastError;

  static bool get isConnected => _connected;
  static int get localSocksPort => _localPort;
  static String? get lastError => _lastError;

  static Future<int> connect(SshProfile profile) async {
    _lastError = 'SSH tunnel needs more research on dartssh2 2.11 API '
        '(coming soon)';
    debugPrint('SshService.connect: stub — $_lastError');
    return 0;
  }

  static Future<void> disconnect() async {
    _connected = false;
    _localPort = 0;
  }

  static Future<bool> ping() async => false;
}
