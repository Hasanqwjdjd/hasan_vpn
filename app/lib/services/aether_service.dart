# مسیر مقصد در ریپو: app/lib/services/aether_service.dart  --  NEW FILE
# ------------------------------------------------------------
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/server.dart';

/// سرویس اتصال از طریق هسته‌ی Aether (پروژه CluvexStudio/Aether).
///
/// Aether یک ابزار دور زدن فیلترینگ است که شبکه را برای مسیرهای قابل دسترس
/// اسکن می‌کند و یک تونل رمزنگاری‌شده می‌سازد، سپس یک پراکسی SOCKS5 محلی
/// (پیش‌فرض 127.0.0.1:1819) و یک پراکسی HTTP CONNECT محلی (پیش‌فرض
/// 127.0.0.1:1820) باز می‌کند.
///
/// سمت Dart فقط پیام‌رسانی با کد Kotlin بومی (AetherVpnService) را انجام
/// می‌دهد؛ خودِ اجرای باینری aether و بالا آوردن VpnService در اندروید
/// انجام می‌شود (پوشه android-extra/kotlin را ببینید).
class AetherService {
  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/aether');

  static bool _connected = false;
  static VpnServer? _current;
  static String? lastError;

  static bool get isConnected => _connected;
  static VpnServer? get current => _current;

  /// مقادیر مجاز: fast | balanced | full
  static const List<String> scanModes = ['fast', 'balanced', 'full'];

  /// مقادیر مجاز: auto | masque_h3 | masque_h2 | wireguard | gool
  static const List<String> protocolModes = [
    'auto',
    'masque_h3',
    'masque_h2',
    'wireguard',
    'gool',
  ];

  /// یک لینک/شناسه‌ی قابل‌ذخیره برای کانفیگ Aether می‌سازد تا در مدل
  /// VpnServer.shareLink ذخیره شود (خودِ Aether هاست/پورت سرور نمی‌خواهد،
  /// چون به‌صورت خودکار مسیر را پیدا می‌کند).
  static String buildConfigLink({
    required String scanMode,
    required String protocolMode,
    String upstreamProxy = '',
  }) {
    final uri = Uri(
      scheme: 'aether',
      host: 'config',
      queryParameters: {
        'scan': scanMode,
        'protocol': protocolMode,
        if (upstreamProxy.isNotEmpty) 'upstream': upstreamProxy,
      },
    );
    return uri.toString();
  }

  static Map<String, String> parseConfigLink(String link) {
    try {
      final uri = Uri.parse(link);
      return uri.queryParameters;
    } catch (_) {
      return const {};
    }
  }

  static Future<bool> connect(VpnServer server) async {
    lastError = null;
    try {
      final cfg = parseConfigLink(server.shareLink);

      // مجوز VpnService را (مثل بقیه‌ی اتصال‌ها) از کاربر می‌گیرد.
      final bool allowed =
          (await _channel.invokeMethod<bool>('prepare')) ?? false;
      if (!allowed) {
        lastError = 'VPN permission denied';
        return false;
      }

      final bool started = (await _channel.invokeMethod<bool>('start', {
            'scanMode': cfg['scan'] ?? 'balanced',
            'protocolMode': cfg['protocol'] ?? 'auto',
            'upstreamProxy': cfg['upstream'] ?? '',
            'remark': server.name,
          })) ??
          false;

      if (!started) {
        lastError = 'Aether core failed to start';
        _connected = false;
        _current = null;
        return false;
      }

      _connected = true;
      _current = server;
      return true;
    } on PlatformException catch (e) {
      lastError = '${e.code}: ${e.message}';
      debugPrint('Aether connect error: $lastError');
      _connected = false;
      _current = null;
      return false;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Aether connect error: $e');
      _connected = false;
      _current = null;
      return false;
    }
  }

  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('Aether disconnect error: $e');
    }
    _connected = false;
    _current = null;
  }

  /// وضعیت زنده از سرویس بومی (اختیاری، برای نمایش جزئیات بیشتر مثل
  /// پروتکل فعال یا پینگ گیت‌وی پیدا‌شده).
  static Future<Map<String, dynamic>> nativeStatus() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('status');
      return res ?? const {};
    } catch (_) {
      return const {};
    }
  }
}
