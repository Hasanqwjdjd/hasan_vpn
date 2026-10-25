import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

/// نگهدارندهٔ نسخهٔ برنامه — یک‌بار در بوت خوانده می‌شود تا UI
/// برای نمایش نسخه منتظر Future نماند.
class PackageInfoProxy {
  PackageInfoProxy._();
  static String version = '';
  static String appName = 'Hasan VPN';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      appName = info.appName;
    } catch (_) {
      version = '';
    }
  }
}
