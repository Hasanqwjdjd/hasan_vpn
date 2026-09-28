import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'warp_endpoint_scanner.dart';

/// حالت‌های اسکن endpoint برای WARP و WARP Plus.
enum WarpEndpointMode { fast, medium, slow, custom }

extension WarpEndpointModeName on WarpEndpointMode {
  String get label => switch (this) {
        WarpEndpointMode.fast => 'Fast',
        WarpEndpointMode.medium => 'Medium',
        WarpEndpointMode.slow => 'Slow',
        WarpEndpointMode.custom => 'Custom',
      };
}

/// WARPSCOUT-style endpoint selection — public API.
///
/// Fast: pool کوچیک ثابت (35 endpoint) — اسکن سریع (~۲ ثانیه)
/// Medium: ۴ /24 × پورت‌های اصلی با نمونه‌گیری (~۱۵ ثانیه)
/// Slow: ۴ /24 × همه پورت‌ها + extended ports (~۶۰ ثانیه)
/// Custom: کاربر endpoint خودش رو می‌ده
class WarpEndpointTester {
  WarpEndpointTester._();

  // ── Pool های استاندارد ─────────────────────────────────────
  static const List<String> _primarySubnets = [
    '188.114.96',
    '188.114.97',
    '162.159.195',
    '8.6.112',
  ];

  static const List<int> _primaryPorts = [2408, 500, 1701, 4500];

  /// Fast — ۳۵ endpoint از Pool های تست‌شده (همون لیست PingNG).
  static const List<String> _fastSeeds = [
    '188.114.97.6:7281', '188.114.97.6:859', '8.6.112.104:4233',
    '8.6.112.106:3138', '8.6.112.107:3138', '8.6.112.121:1180',
    '8.6.112.122:894', '8.6.112.127:4198', '8.6.112.133:968',
    '8.6.112.139:7281', '8.6.112.154:891', '8.6.112.182:891',
    '188.114.98.27:890', '188.114.99.119:891',
    '188.114.96.62:894', '188.114.97.124:903', '188.114.96.1:1701',
    '162.159.195.54:864', '162.159.192.60:859', '188.114.97.114:880',
    '162.159.192.121:903', '188.114.97.121:968', '188.114.98.53:890',
    '162.159.195.56:864', '162.159.195.68:864', '162.159.192.132:903',
    '188.114.97.174:880', '188.114.96.76:878', '188.114.96.166:878',
    '188.114.96.206:878', '162.159.192.1:2408', '8.34.146.150:1701',
    '162.159.192.96:939',
  ];

  /// Slow — پورت‌های اضافی WARPSCOUT.
  static const List<int> _extendedPorts = [
    854, 859, 864, 878, 880, 890, 891, 894, 903, 908,
    928, 934, 939, 942, 943, 945, 946, 955, 968, 987,
    988, 1002, 1010, 1014, 1018, 1070, 1074, 1180, 1387, 1843,
    2371, 2506, 3138, 3476, 3581, 3854, 4177, 4198, 4233, 5279,
    5956, 7103, 7152, 7156, 7281, 7559, 8319, 8742, 8854, 8886,
  ];

  static const String _prefLastFast = 'warp_scout_last_fast_v1';
  static const String _prefLastSlow = 'warp_scout_last_slow_v1';

  /// انتخاب endpoint با حالت مشخص. [privateKeyB64] و [peerPublicKeyB64]
  /// از WARP account میان (b64 استاندارد WireGuard).
  static Future<WarpEndpointHit?> select({
    required WarpEndpointMode mode,
    required String privateKeyB64,
    required String peerPublicKeyB64,
    String? customEndpoint,
    void Function(String label, int tested, int total)? onProgress,
  }) async {
    final priv = _tryDecodeB64(privateKeyB64);
    final peer = _tryDecodeB64(peerPublicKeyB64);
    if (priv == null || peer == null) {
      debugPrint('warp_scout: invalid key format');
      return null;
    }

    // در حالت Custom فقط همون endpoint رو تست کن.
    if (mode == WarpEndpointMode.custom) {
      final custom = _parseEndpoint(customEndpoint);
      if (custom == null) return null;
      final hits = await WarpEndpointScanner.scan(
        endpoints: [custom],
        privateKey: priv,
        peerPublicKey: peer,
        ratePerSecond: 0,
        workers: 1,
        timeoutMs: 800,
        maxHits: 1,
        acceptCookieReplies: true,
        onProgress: (t, total) => onProgress?.call('Custom', t, total),
      );
      return hits.isEmpty ? null : hits.first;
    }

    // 1) reconnect — اگه endpoint قبلاً انتخاب شده، اول اون رو تست کن.
    final cached = await _cachedEndpoint(mode);
    if (cached != null) {
      final hits = await WarpEndpointScanner.scan(
        endpoints: [cached],
        privateKey: priv,
        peerPublicKey: peer,
        ratePerSecond: 0,
        workers: 1,
        timeoutMs: 600,
        maxHits: 1,
        acceptCookieReplies: true,
        onProgress: (t, total) =>
            onProgress?.call('Reconnect', t, total),
      );
      if (hits.isNotEmpty) return hits.first;
    }

    // 2) اسکن اصلی
    final List<WarpEndpoint> pool;
    final int workers;
    final int timeoutMs;
    final int? samplePerSubnet;
    final int? stopAfterHits;
    final int ratePerSecond;

    switch (mode) {
      case WarpEndpointMode.fast:
        pool = _fastSeeds
            .map(_parseEndpoint)
            .whereType<WarpEndpoint>()
            .toList();
        workers = 64;
        timeoutMs = 400;
        samplePerSubnet = null;
        stopAfterHits = 8;
        ratePerSecond = 1500;
        break;
      case WarpEndpointMode.medium:
        pool = WarpEndpointScanner.buildPool(
          subnets: _primarySubnets,
          ports: _primaryPorts,
          sampleHostsPerSubnet: 32,
        );
        workers = 128;
        timeoutMs = 500;
        samplePerSubnet = 32;
        stopAfterHits = 16;
        ratePerSecond = 3500;
        break;
      case WarpEndpointMode.slow:
        pool = WarpEndpointScanner.buildPool(
          subnets: _primarySubnets,
          ports: [..._primaryPorts, ..._extendedPorts],
        );
        workers = 256;
        timeoutMs = 350;
        samplePerSubnet = null;
        stopAfterHits = null;
        ratePerSecond = 2000;
        break;
      case WarpEndpointMode.custom:
        return null;
    }

    final label = mode.label;
    final hits = await WarpEndpointScanner.scan(
      endpoints: pool,
      privateKey: priv,
      peerPublicKey: peer,
      ratePerSecond: ratePerSecond,
      workers: workers,
      timeoutMs: timeoutMs,
      maxHits: 64,
      stopAfterHits: stopAfterHits,
      acceptCookieReplies: mode != WarpEndpointMode.fast,
      onProgress: (t, total) => onProgress?.call(label, t, total),
    );

    if (hits.isEmpty) return null;
    // در Fast/Medium ترتیب کشف (WARPSCOUT-style) بهتره.
    // در Slow تأخیر خام سریع‌ترین رو انتخاب کن.
    hits.sort(mode == WarpEndpointMode.slow
        ? (a, b) => a.latencyMs.compareTo(b.latencyMs)
        : (a, b) => a.discoveryOrder.compareTo(b.discoveryOrder));
    final best = hits.first;
    await _saveCachedEndpoint(mode, best.endpoint);
    return best;
  }

  /// نسخه چند-برنده `select`: لیست hit ها رو برمی‌گردونه برای verify.
  ///
  /// برای WARP Plus / WARP که می‌خوان real-tunnel verify کنن لازمه —
  /// چون UDP handshake تضمین نمی‌کنه data-plane کار کنه.
  static Future<List<WarpEndpointHit>> selectMany({
    required WarpEndpointMode mode,
    required String privateKeyB64,
    required String peerPublicKeyB64,
    String? customEndpoint,
    int maxHits = 12,
    void Function(String label, int tested, int total)? onProgress,
  }) async {
    final priv = _tryDecodeB64(privateKeyB64);
    final peer = _tryDecodeB64(peerPublicKeyB64);
    if (priv == null || peer == null) return const [];

    if (mode == WarpEndpointMode.custom) {
      final custom = _parseEndpoint(customEndpoint);
      if (custom == null) return const [];
      final hits = await WarpEndpointScanner.scan(
        endpoints: [custom],
        privateKey: priv,
        peerPublicKey: peer,
        ratePerSecond: 0,
        workers: 1,
        timeoutMs: 800,
        maxHits: 1,
        acceptCookieReplies: true,
        onProgress: (t, total) => onProgress?.call('Custom', t, total),
      );
      return hits;
    }

    // reconnect — اگه cached بود، اول اون رو با priority برگردون
    final cached = await _cachedEndpoint(mode);
    final List<WarpEndpointHit> cachedHits;
    if (cached != null) {
      cachedHits = await WarpEndpointScanner.scan(
        endpoints: [cached],
        privateKey: priv,
        peerPublicKey: peer,
        ratePerSecond: 0,
        workers: 1,
        timeoutMs: 600,
        maxHits: 1,
        acceptCookieReplies: true,
        onProgress: (t, total) =>
            onProgress?.call('Reconnect', t, total),
      );
    } else {
      cachedHits = const [];
    }

    final List<WarpEndpoint> pool;
    final int workers;
    final int timeoutMs;
    final int? stopAfterHits;
    final int ratePerSecond;

    switch (mode) {
      case WarpEndpointMode.fast:
        pool = _fastSeeds
            .map(_parseEndpoint)
            .whereType<WarpEndpoint>()
            .toList();
        workers = 64;
        timeoutMs = 400;
        stopAfterHits = maxHits;
        ratePerSecond = 1500;
        break;
      case WarpEndpointMode.medium:
        pool = WarpEndpointScanner.buildPool(
          subnets: _primarySubnets,
          ports: _primaryPorts,
          sampleHostsPerSubnet: 32,
        );
        workers = 128;
        timeoutMs = 500;
        stopAfterHits = maxHits;
        ratePerSecond = 3500;
        break;
      case WarpEndpointMode.slow:
        pool = WarpEndpointScanner.buildPool(
          subnets: _primarySubnets,
          ports: [..._primaryPorts, ..._extendedPorts],
        );
        workers = 256;
        timeoutMs = 350;
        stopAfterHits = null;
        ratePerSecond = 2000;
        break;
      case WarpEndpointMode.custom:
        return const [];
    }

    final label = mode.label;
    final hits = await WarpEndpointScanner.scan(
      endpoints: pool,
      privateKey: priv,
      peerPublicKey: peer,
      ratePerSecond: ratePerSecond,
      workers: workers,
      timeoutMs: timeoutMs,
      maxHits: maxHits.clamp(1, 64),
      stopAfterHits: stopAfterHits,
      acceptCookieReplies: mode != WarpEndpointMode.fast,
      onProgress: (t, total) => onProgress?.call(label, t, total),
    );

    // cached اول، بعد بقیه
    final out = <WarpEndpointHit>[];
    if (cachedHits.isNotEmpty) out.addAll(cachedHits);
    out.addAll(hits);

    // dedup
    final seen = <String>{};
    out.retainWhere((h) => seen.add(h.endpoint.toString()));

    if (out.isEmpty) return const [];
    out.sort(mode == WarpEndpointMode.slow
        ? (a, b) => a.latencyMs.compareTo(b.latencyMs)
        : (a, b) => a.discoveryOrder.compareTo(b.discoveryOrder));
    return out;
  }

  /// چک کردن اینکه endpoint قبلاً تست شده.
  static Future<WarpEndpoint?> _cachedEndpoint(WarpEndpointMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = mode == WarpEndpointMode.fast ? _prefLastFast : _prefLastSlow;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      return _parseEndpoint(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCachedEndpoint(
    WarpEndpointMode mode,
    WarpEndpoint endpoint,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = mode == WarpEndpointMode.fast ? _prefLastFast : _prefLastSlow;
      await prefs.setString(key, endpoint.toString());
    } catch (_) {}
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLastFast);
      await prefs.remove(_prefLastSlow);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────

  static Uint8List? _tryDecodeB64(String value) {
    try {
      final normalized = value
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      final padded = normalized.padRight(
          (normalized.length + 3) & ~3, '=');
      final out = base64.decode(padded);
      return out.length == 32 ? out : null;
    } catch (_) {
      return null;
    }
  }

  static WarpEndpoint? _parseEndpoint(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.startsWith('[')) {
      final close = text.indexOf(']');
      if (close <= 1) return null;
      final host = text.substring(1, close);
      final port =
          int.tryParse(text.substring(close + 1).replaceFirst(':', ''));
      if (port == null || port < 1 || port > 65535) return null;
      return WarpEndpoint(host, port);
    }
    final sep = text.lastIndexOf(':');
    if (sep <= 0) return null;
    final host = text.substring(0, sep);
    final port = int.tryParse(text.substring(sep + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return WarpEndpoint(host, port);
  }

  /// لیست کامل endpoint ها در هر mode (برای UI پیش‌نمایش).
  static int poolSize(WarpEndpointMode mode) {
    switch (mode) {
      case WarpEndpointMode.fast:
        return _fastSeeds.length;
      case WarpEndpointMode.medium:
        return _primarySubnets.length * 32 * _primaryPorts.length;
      case WarpEndpointMode.slow:
        return _primarySubnets.length * 256 * (_primaryPorts.length + _extendedPorts.length);
      case WarpEndpointMode.custom:
        return 1;
    }
  }

  static Random get randomForTests => Random();
}
