import 'package:flutter/services.dart';

class AntiSanctionService {
  AntiSanctionService._();

  static const MethodChannel _ch =
      MethodChannel('com.hasan.hasan_vpn/sanction');

  static Future<Map<String, dynamic>> status() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('status', {});
      return r ??
          {'filterBypass': false, 'geminiFix': false, 'geminiUsExit': false};
    } catch (_) {
      return {'filterBypass': false, 'geminiFix': false, 'geminiUsExit': false};
    }
  }

  static Future<Map<String, dynamic>> setFilterBypass(bool enabled) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>(
          'setFilterBypass', {'enabled': enabled});
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> setGeminiFix(bool enabled) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>(
          'setGeminiFix', {'enabled': enabled});
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> setGeminiUsExit(bool enabled) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>(
          'setGeminiUsExit', {'enabled': enabled});
      return r ?? {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
