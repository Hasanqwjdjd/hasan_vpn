import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// رصد تغییرات شبکه (4G ↔ WiFi ↔ قطع کامل).
/// وقتی شبکه عوض می‌شود، callback صدا زده می‌شود تا VPN دوباره وصل شود.
class ConnectivityWatcher {
  ConnectivityWatcher._();
  static final ConnectivityWatcher instance = ConnectivityWatcher._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _last = const [ConnectivityResult.none];
  bool _wasOnline = false;

  /// آخرین وضعیت: حداقل یک اینترفیس فعال.
  bool get isOnline => _wasOnline;

  /// شروع رصد. callback وقتی وضعیت از offline→online برگردد صدا زده می‌شود.
  /// (تغییر WiFi→4G هم باعث صدا زدن می‌شود چون transport عوض شده).
  void start(void Function() onReconnected) {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      // FIX CRITICAL: VPN interface خودِ تونل ماست — نباید تراکنش شبکه‌ای
      // حساب شه. اگر VPN را فعال کنی، ConnectivityWatcher فکر می‌کند
      // شبکه عوض شد و auto-reconnect می‌زند که تونل را می‌کشد → حلقه
      // بی‌نهایت disconnect وصل شو.
      final filtered =
          results.where((r) => r != ConnectivityResult.vpn).toList();
      final online = filtered.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      final wasOnline = _wasOnline;
      final lastSet =
          _last.where((r) => r != ConnectivityResult.vpn).toSet();
      final newSet = filtered.toSet();

      // اگر فقط VPN interface تغییر کرده، هیچ کاری نکن
      if (lastSet.length == newSet.length &&
          lastSet.containsAll(newSet) &&
          newSet.containsAll(lastSet)) {
        return;
      }

      _last = filtered;
      _wasOnline = online;

      if (!wasOnline && online) {
        debugPrint('ConnectivityWatcher: reconnected');
        onReconnected();
      } else if (wasOnline &&
          online &&
          !lastSet.containsAll(newSet) &&
          lastSet.isNotEmpty) {
        debugPrint('ConnectivityWatcher: transport changed');
        onReconnected();
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
