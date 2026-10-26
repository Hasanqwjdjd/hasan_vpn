import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'minisign.dart';

/// استور موتورها — پورت `scanner/store/StoreManager.kt` (مسیر SignedManifest).
///
/// هستهٔ Geph هیچ باینری اندروید مستقیمی منتشر نمی‌کند؛ رسمی‌ترین مسیر
/// (همان مسیر MLM): فهرست نسخه‌های امضاشدهٔ خود گف → دانلود APK رسمی →
/// بررسی sha256 → استخراج lib/arm64-v8a/libgeph.so بدون هیچ تغییری.
class StoreService {
  StoreService._();

  static const MethodChannel _ch = MethodChannel('com.hasan.hasan_vpn/store');

  static const List<String> gephMirrors = [
    'https://f001.backblazeb2.com/file/geph4-dl/geph-releases',
    'https://sos-ch-dk-2.exo.io/utopia/geph-releases-new',
  ];

  /// کلید عمومی minisign خود گف — پین‌شده، عیناً مثل MLM StoreCatalog.
  static const String gephMinisignKey =
      'RWSzEWRCN0AaNpPj+yw0zbOI87jI8PNpnCoITCroKQxRAANAzUawpph7';
  static const String gephTrack = 'android-stable';

  static String? _cachedVersion;
  static String? get gephInstalledVersion => _cachedVersion;

  static Future<Directory> _storeDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/store/items/geph');
  }

  static Future<String> gephBinaryPath() async {
    final dir = await _storeDir();
    return '${dir.path}/libgeph.so';
  }

  static Future<bool> gephInstalled() async {
    final p = await gephBinaryPath();
    final f = File(p);
    final ok = await f.exists() && await f.length() > 1024 * 1024;
    if (ok && _cachedVersion == null) {
      final prefs = await _loadPrefs();
      _cachedVersion = prefs['geph_version'];
    }
    return ok;
  }

  static Future<Map<String, String>> _loadPrefs() async {
    try {
      final dir = await _storeDir();
      final f = File('${dir.path}/meta.json');
      if (!await f.exists()) return {};
      final dec = jsonDecode(await f.readAsString());
      if (dec is Map) {
        return dec.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _savePrefs(Map<String, String> p) async {
    final dir = await _storeDir();
    await dir.create(recursive: true);
    await File('${dir.path}/meta.json').writeAsString(jsonEncode(p));
  }

  /// فهرست نسخهٔ امضاشدهٔ گف را می‌خواند؛ خروجی: نسخه + آدرس APK + sha256.
  static Future<({String version, String url, String sha256})?>
      gephLatest() async {
    Object? lastError;
    for (final base in gephMirrors) {
      try {
        final yaml = await _getText('$base/metadata.yaml');
        final sig = await _getText('$base/metadata.yaml.minisig');
        final ok = await Minisign.verify(
          utf8.encode(yaml),
          sig,
          gephMinisignKey,
        );
        if (!ok) {
          throw StoreException(
              'امضای فهرست نسخه‌های گف درست نبود؛ چیزی نصب نخواهد شد.');
        }
        final entry = SignedManifestYaml.entry(yaml, gephTrack);
        if (entry == null) {
          throw StoreException('گف نسخهٔ اندرویدی منتشر نکرده است.');
        }
        return (
          version: entry.version,
          url: '$base/$gephTrack/${entry.version}/${entry.filename}',
          sha256: entry.sha256,
        );
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      debugPrint('[Store] gephLatest failed: $lastError');
    }
    return null;
  }

  /// دانلود + تأیید هش + استخراج libgeph.so + اجرای آزمایشی.
  /// [onProgress]: (دانلودشده، کل) به بایت.
  static Future<bool> installGeph({
    void Function(String msg)? onLog,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    final latest = await gephLatest();
    if (latest == null) {
      onLog?.call('هیچ آینه‌ای از گف پاسخ نداد / امضا نامعتبر بود');
      return false;
    }
    onLog?.call('نسخهٔ ${latest.version} پیدا شد — دانلود APK رسمی…');

    final tmp = await getTemporaryDirectory();
    final apkPath = '${tmp.path}/geph-android-${latest.version}.apk';
    final ok = await _download(latest.url, apkPath, onProgress,
        expectedSha256: latest.sha256);
    if (!ok) {
      AppLog.e('STORE', 'download/sha256 failed for ${latest.url}');
      onLog?.call('دانلود یا بررسی هش ناموفق بود');
      return false;
    }
    AppLog.i('STORE', 'sha256 OK — extracting libgeph.so');
    onLog?.call('هش تأیید شد — استخراج libgeph.so…');

    try {
      final bytes = await File(apkPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      File? so;
      for (final f in archive.files) {
        if (f.name == 'lib/arm64-v8a/libgeph.so') {
          so = File(await gephBinaryPath());
          await so.parent.create(recursive: true);
          await so.writeAsBytes(f.content as List<int>);
          break;
        }
      }
      if (so == null) {
        onLog?.call('بستهٔ رسمی libgeph.so (arm64) نداشت');
        return false;
      }
      // اجرای آزمایشی — هسته باید با --help بالا بیاید (مثل MLM).
      final probe = await _ch.invokeMapMethod<String, dynamic>(
        'probe',
        {'path': so.path, 'args': ['--help']},
      );
      final probeOk = probe?['ok'] == true;
      await _savePrefs({'geph_version': latest.version});
      _cachedVersion = latest.version;
      onLog?.call(probeOk
          ? 'هستهٔ گف ${latest.version} نصب و آزمایش شد'
          : 'نصب شد ولی اجرای آزمایشی جواب نداد');
      try {
        await File(apkPath).delete();
      } catch (_) {}
      return true;
    } catch (e) {
      onLog?.call('استخراج ناموفق: $e');
      return false;
    }
  }

  static Future<bool> _download(
    String url,
    String savePath,
    void Function(int, int)? onProgress, {
    String? expectedSha256,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return false;
      final total = resp.contentLength;
      final sink = File(savePath).openWrite();
      var received = 0;
      final digest = crypto.sha256;
      final output = _DigestSink(digest);
      await for (final chunk in resp) {
        received += chunk.length;
        sink.add(chunk);
        output.add(chunk);
        if (onProgress != null && total > 0) {
          onProgress(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      if (expectedSha256 != null && output.hex != expectedSha256) {
        debugPrint('[Store] sha mismatch: ${output.hex} != $expectedSha256');
        return false;
      }
      return true;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _getText(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw StoreException('HTTP ${resp.statusCode}');
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

class StoreException implements Exception {
  final String message;
  StoreException(this.message);
  @override
  String toString() => message;
}

/// جمع‌کنندهٔ هش جریانی.
class _DigestSink {
  final crypto.Hash _algorithm;
  crypto.Digest? _digest;
  final List<List<int>> _chunks = [];
  _DigestSink(this._algorithm);
  void add(List<int> chunk) => _chunks.add(chunk);
  String get hex {
    _digest ??= _algorithm.convert(_chunks.expand((c) => c).toList());
    return _digest!.toString();
  }
}
