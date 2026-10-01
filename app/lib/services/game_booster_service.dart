import 'package:flutter/services.dart';

/// Flutter wrapper for com.hasan.hasan_vpn/game_booster MethodChannel.
class GameBoosterService {
  GameBoosterService._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/game_booster');

  static Future<Map<String, dynamic>> raceDns({
    String hostname = 'pubgmobile.com',
  }) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('raceDns', {
        'hostname': hostname,
      });
      return r ?? {'ok': false, 'results': <dynamic>[]};
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'results': <dynamic>[]};
    }
  }

  static Future<List<Map<String, dynamic>>> listGames() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('listGames', {});
      final games = r?['games'];
      if (games is List) {
        return games
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> pingGame(
    String id, {
    String? region,
  }) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('pingGame', {
        'id': id,
        if (region != null) 'region': region,
      });
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> startDnsBoost(
    String resolver, {
    String? secondary,
  }) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('startDnsBoost', {
        'resolver': resolver,
        if (secondary != null) 'secondary': secondary,
      });
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> stopDnsBoost() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('stopDnsBoost', {});
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status', {});
      return r ?? {'running': false};
    } catch (_) {
      return {'running': false};
    }
  }
}
