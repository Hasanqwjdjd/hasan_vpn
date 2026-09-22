import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// درخواست اتصال از ویجت صفحهٔ اصلی.
class WidgetConnectRequest {
  /// connect = باز شدن UI + اتصال خودکار (۲×۱)
  /// bg_connect = اتصال با کمترین UI (۱×۱)
  final String action;
  final String type; // server | dns | tor
  final String payload;
  final String title;
  final bool autoConnect;
  final bool bgConnect;

  const WidgetConnectRequest({
    required this.action,
    required this.type,
    required this.payload,
    required this.title,
    this.autoConnect = true,
    this.bgConnect = false,
  });

  bool get isEmpty => payload.isEmpty && type.isEmpty;
}

/// خواندن Intent ویجت از:
/// ۱) SharedPreferences (نوشته‌شده توسط WidgetBgConnectActivity)
/// ۲) MethodChannel از MainActivity (اختیاری)
class WidgetConnectHandler {
  WidgetConnectHandler._();

  static const MethodChannel _channel =
      MethodChannel('com.hasan.hasan_vpn/widget');

  static const String _kAction = 'widget_pending_action';
  static const String _kType = 'widget_pending_type';
  static const String _kPayload = 'widget_pending_payload';
  static const String _kTitle = 'widget_pending_title';
  static const String _kAuto = 'widget_pending_auto';

  /// یک‌بار در شروع اپ / resume صدا زده شود.
  static Future<WidgetConnectRequest?> consumePending() async {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString(_kAction);
    final type = prefs.getString(_kType) ?? '';
    final payload = prefs.getString(_kPayload) ?? '';
    final title = prefs.getString(_kTitle) ?? '';
    final auto = prefs.getBool(_kAuto) ?? true;

    // پاک کردن تا دوباره اجرا نشود
    await prefs.remove(_kAction);
    await prefs.remove(_kType);
    await prefs.remove(_kPayload);
    await prefs.remove(_kTitle);
    await prefs.remove(_kAuto);

    if (action == null || action.isEmpty) {
      // تلاش از MethodChannel (اگر MainActivity extras را push کند)
      try {
        final map = await _channel.invokeMethod<Map>('getLaunchExtras');
        if (map != null) {
          final a = map['widget_action']?.toString() ?? '';
          final p = map['widget_payload']?.toString() ?? '';
          if (a.isNotEmpty && p.isNotEmpty) {
            return WidgetConnectRequest(
              action: a,
              type: map['widget_type']?.toString() ?? 'server',
              payload: p,
              title: map['widget_title']?.toString() ?? '',
              autoConnect: map['widget_auto_connect'] == true ||
                  map['widget_auto_connect']?.toString() == 'true',
              bgConnect: map['widget_bg_connect'] == true ||
                  a == 'bg_connect',
            );
          }
        }
      } catch (_) {}
      return null;
    }

    if (payload.isEmpty) return null;

    return WidgetConnectRequest(
      action: action,
      type: type.isEmpty ? 'server' : type,
      payload: payload,
      title: title,
      autoConnect: auto,
      bgConnect: action == 'bg_connect',
    );
  }

  /// ثبت listener برای وقتی MainActivity extras جدید می‌فرستد.
  /// [onRequest] برای درخواست‌های اتصال معمولی (2×1 / 1×1 با binding).
  /// [onNeedsServer] وقتی اپ از قبل باز/زنده است و ویجت ۱×۱ بدون binding
  /// کلیک می‌شود؛ MainActivity این را از طریق onNewIntent پوش می‌کند اما
  /// قبلاً این تابع widget_needs_server را نادیده می‌گرفت (باگ #1).
  static void listen(
    void Function(WidgetConnectRequest req) onRequest, {
    void Function(int widgetId)? onNeedsServer,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetIntent') {
        final args = call.arguments;
        if (args is Map) {
          if (args['widget_needs_server'] == true) {
            final wid = (args['widget_id'] as num?)?.toInt();
            if (wid != null && wid > 0) {
              onNeedsServer?.call(wid);
            }
            return null;
          }

          final action = args['widget_action']?.toString() ?? 'connect';
          final payload = args['widget_payload']?.toString() ?? '';
          if (payload.isEmpty) return null;
          onRequest(WidgetConnectRequest(
            action: action,
            type: args['widget_type']?.toString() ?? 'server',
            payload: payload,
            title: args['widget_title']?.toString() ?? '',
            autoConnect: true,
            bgConnect: action == 'bg_connect' ||
                args['widget_bg_connect'] == true,
          ));
        }
      }
      return null;
    });
  }
}
