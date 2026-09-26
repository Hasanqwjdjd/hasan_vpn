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
      final online = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn);
      final wasOnline = _wasOnline;
      final lastSet = _last.toSet();
      final newSet = results.toSet();

      _last = results;
      _wasOnline = online;

      if (!wasOnline && online) {
        // offline → online
        debugPrint('ConnectivityWatcher: reconnected');
        onReconnected();
      } else if (wasOnline &&
          online &&
          !lastSet.containsAll(newSet) &&
          lastSet.isNotEmpty) {
        // transport عوض شد (WiFi ↔ cellular)
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
