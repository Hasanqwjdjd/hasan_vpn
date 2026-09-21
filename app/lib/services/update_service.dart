import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class UpdateInfo {
  final String tag;
  final String version;
  final String apkUrl;
  final String pageUrl;
  final String abi;
  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.apkUrl,
    required this.pageUrl,
    required this.abi,
  });
}

class UpdateService {
  UpdateService._();

  static const String repo = 'Hasanqwjdjd/hasan_vpn';
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/device');

  static Future<String> detectAbi() async {
    try {
      final list = await _channel.invokeListMethod<String>('abis');
      if (list != null) {
        for (final a in list) {
          if (a == 'arm64-v8a') return 'arm64';
          if (a == 'armeabi-v7a') return 'arm32';
          if (a == 'x86_64') return 'x86_64';
        }
      }
    } catch (_) {}
    final v = Platform.version;
    if (v.contains('arm64')) return 'arm64';
    if (v.contains('x64')) return 'x86_64';
    if (v.contains('arm')) return 'arm32';
    return 'arm64';
  }

  static String _suffix(String abi) {
    switch (abi) {
      case 'arm32':
        return '-32bit';
      case 'x86_64':
        return '-x86_64';
      default:
        return '';
    }
  }

  static bool _matches(String name, String abi) {
    final n = name.toLowerCase();
    if (!n.endsWith('.apk')) return false;
    final is32 = n.endsWith('-32bit.apk');
    final isX86 = n.endsWith('-x86_64.apk');
    switch (abi) {
      case 'arm32':
        return is32;
      case 'x86_64':
        return isX86;
      default:
        return !is32 && !isX86;
    }
  }

  static Future<String?> _tagFromRedirect() async {
    final client = http.Client();
    try {
      final req = http.Request(
          'GET', Uri.parse('https://github.com/$repo/releases/latest'))
        ..followRedirects = false;
      final res = await client.send(req).timeout(const Duration(seconds: 15));
      final loc = res.headers['location'] ?? '';
      final i = loc.lastIndexOf('/tag/');
      if (i >= 0) return Uri.decodeComponent(loc.substring(i + 5));
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  static Future<UpdateInfo> fetchLatest() async {
    final abi = await detectAbi();
    String? tag;
    String? apk;
    var pageUrl = 'https://github.com/$repo/releases/latest';

    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          tag = data['tag_name']?.toString();
          pageUrl = data['html_url']?.toString() ?? pageUrl;
          final assets = data['assets'];
          if (assets is List) {
            for (final a in assets) {
              if (a is! Map) continue;
              final name = a['name']?.toString() ?? '';
              final url = a['browser_download_url']?.toString() ?? '';
              if (url.isNotEmpty && _matches(name, abi)) {
                apk = url;
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    tag ??= await _tagFromRedirect();
    if (tag == null || tag.isEmpty) {
      throw Exception('release not found');
    }
    apk ??=
        'https://github.com/$repo/releases/download/$tag/Hasan-VPN-$tag${_suffix(abi)}.apk';
    final version = tag.replaceAll('v', '').split('.').take(3).join('.');
    return UpdateInfo(
      tag: tag,
      version: version,
      apkUrl: apk,
      pageUrl: pageUrl,
      abi: abi,
    );
  }
}
