import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// تأیید امضای minisign — پورت ۱:۱ از `scanner/store/Minisign.kt` (MLM VPN).
///
/// دو قالب: «Ed» (امضا روی خود فایل) و «ED» (امضا روی BLAKE2b-512 فایل).
/// علاوه بر امضای اصلی، «trusted comment» هم جداگانه امضا شده و بررسی
/// می‌شود تا نه فایل و نه کامنت نتواند جابه‌جا شود.
class Minisign {
  Minisign._();

  static Future<bool> verify(
    List<int> data,
    String signatureFile,
    String publicKeyB64,
  ) async {
    try {
      final pk = _decode(publicKeyB64);
      if (pk.length != 42 ||
          pk[0] != 0x45 /* E */ ||
          pk[1] != 0x64 /* d */) {
        return false;
      }
      final keyId = Uint8List.sublistView(pk, 2, 10);
      final key = Uint8List.sublistView(pk, 10, 42);

      final lines = signatureFile.split('\n');
      if (lines.length < 4) return false;
      final sig = _decode(lines[1].trim());
      if (sig.length != 74) return false;
      final alg = latin1.decode(Uint8List.sublistView(sig, 0, 2));
      final sigKeyId = Uint8List.sublistView(sig, 2, 10);
      for (var i = 0; i < 8; i++) {
        if (sigKeyId[i] != keyId[i]) return false;
      }
      final signature = Uint8List.sublistView(sig, 10, 74);

      Uint8List message;
      switch (alg) {
        case 'ED':
          final blake = Blake2b(hashLengthInBytes: 64);
          final hash = await blake.hash(data);
          message = Uint8List.fromList(hash.bytes);
          break;
        case 'Ed':
          message = Uint8List.fromList(data);
          break;
        default:
          return false;
      }

      final algo = Ed25519();
      final pub = SimplePublicKey(key, type: KeyPairType.ed25519);
      final ok = await algo.verify(
        message,
        signature: Signature(signature, publicKey: pub),
      );
      if (!ok) return false;

      // global signature: روی (امضای اصلی + بایت‌های trusted comment)
      final trusted = lines[2];
      const prefix = 'trusted comment: ';
      if (!trusted.startsWith(prefix)) return false;
      final comment = utf8.encode(trusted.substring(prefix.length));
      final global = _decode(lines[3].trim());
      if (global.length != 64) return false;
      final combined = <int>[...sig.sublist(0, 74), ...comment];
      return await algo.verify(
        combined,
        signature: Signature(global, publicKey: pub),
      );
    } catch (_) {
      return false;
    }
  }

  /// base64 استاندارد (padding اختیاری) — مثل decode در Minisign.kt.
  static Uint8List _decode(String b64) {
    final alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final clean = b64
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('=', '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final c in clean.split('')) {
      final v = alphabet.indexOf(c);
      if (v < 0) throw ArgumentError('not base64');
      buffer = (buffer << 6) | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }
}

/// فقط بلاک موردنیاز از `metadata.yaml` سازنده: نسخه/هش/فایل یک track.
/// پورت `SignedManifestYaml` از MLM.
class SignedManifestYaml {
  SignedManifestYaml._();

  static ({String version, String sha256, String filename})? entry(
    String yaml,
    String track,
  ) {
    final lines = yaml.split('\n');
    final start =
        lines.indexWhere((l) => l.trimRight() == '$track:');
    if (start < 0) return null;
    final fields = <String, String>{};
    for (final line in lines.skip(start + 1)) {
      if (line.trim().isEmpty) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) break;
      final m = RegExp(r'^\s+([a-z0-9_]+):\s*(\S+)\s*$').firstMatch(line);
      if (m == null) continue;
      fields[m.group(1)!] =
          m.group(2)!.replaceAll('"', '').replaceAll("'", '');
    }
    final version = fields['version'];
    final sha = fields['sha256'];
    final file = fields['filename'];
    if (version == null || sha == null || file == null) return null;
    if (sha.length != 64) return null;
    return (version: version, sha256: sha.toLowerCase(), filename: file);
  }
}
