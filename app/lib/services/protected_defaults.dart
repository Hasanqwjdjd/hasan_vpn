import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'protected_defaults.g.dart';

/// اشتراک‌های پیش‌فرض (رایگان) برنامه.
///
/// لینک‌ها فقط به‌صورت رمزشده در برنامه هستند (تولید در CI از GitHub Secret)،
/// در سورس/ریپو نیستند، در UI نشان داده نمی‌شوند و در SharedPreferences
/// ذخیره نمی‌شوند. رمزگشایی فقط لحظهٔ دانلود انجام می‌شود.
///
/// توجه: هر چیزی که برنامه برای اتصال لازم دارد را کاربرِ مصمم با ابزار
/// مهندسی معکوس می‌تواند دربیاورد؛ این لایه فقط سطح را بالا می‌برد.
class ProtectedDefaults {
  ProtectedDefaults._();

  static List<List<String>> get entries => kProtectedEntries;

  static bool has(String id) => entries.any((e) => e[0] == id);

  /// لینک واقعی اشتراک پیش‌فرض یا null اگر نبود / رمزگشایی نشد.
  static String? urlFor(String id) {
    for (final e in entries) {
      if (e[0] == id) return _decrypt(e[2]);
    }
    return null;
  }

  static Uint8List? _masterKey() {
    final n = kPk1.length;
    if (n == 0 || kPk2.length != n || kPk3.length != n || kPk4.length != n) {
      return null;
    }
    final key = Uint8List(n);
    for (var i = 0; i < n; i++) {
      key[i] = (kPk1[i] ^ kPk2[i] ^ kPk3[i] ^ kPk4[i]) & 0xFF;
    }
    return key;
  }

  static List<int> _block(Hmac hmac, List<int> nonce, int counter) {
    final msg = <int>[
      ...utf8.encode('enc'),
      ...nonce,
      (counter >> 24) & 0xFF,
      (counter >> 16) & 0xFF,
      (counter >> 8) & 0xFF,
      counter & 0xFF,
    ];
    return hmac.convert(msg).bytes;
  }

  static String? _decrypt(String blobB64) {
    try {
      final key = _masterKey();
      if (key == null) return null;

      final raw = base64.decode(blobB64);
      if (raw.length < 12 + 16) return null;

      final nonce = raw.sublist(0, 12);
      final ct = raw.sublist(12, raw.length - 16);
      final tag = raw.sublist(raw.length - 16);

      final hmac = Hmac(sha256, key);
      final macFull =
          hmac.convert(<int>[...utf8.encode('mac'), ...nonce, ...ct]).bytes;

      // مقایسهٔ زمان-ثابت برچسب صحت
      var diff = 0;
      for (var i = 0; i < 16; i++) {
        diff |= macFull[i] ^ tag[i];
      }
      if (diff != 0) return null;

      final out = Uint8List(ct.length);
      for (var off = 0, ctr = 0; off < ct.length; off += 32, ctr++) {
        final ks = _block(hmac, nonce, ctr);
        for (var j = 0; j < 32 && off + j < ct.length; j++) {
          out[off + j] = ct[off + j] ^ ks[j];
        }
      }
      return utf8.decode(out);
    } catch (_) {
      return null;
    }
  }
}
