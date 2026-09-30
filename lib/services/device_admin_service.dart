import 'package:flutter/services.dart';

import '../config.dart';

class DeviceAdminService {
  static const MethodChannel platform = MethodChannel('device_admin_channel');

  static Future<bool> _bool(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await platform.invokeMethod(method, args);
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // ---- Permission status ----
  static Future<bool> isAdminActive() => _bool('isAdminActive');
  static Future<bool> isOverlayGranted() => _bool('isOverlayGranted');
  static Future<bool> isAccessibilityEnabled() =>
      _bool('isAccessibilityEnabled');
  static Future<bool> isBatteryIgnored() => _bool('isBatteryIgnored');

  // ---- Permission requests (each opens the right Settings page) ----
  static Future<void> requestAdmin() => _bool('requestAdmin');
  static Future<void> requestOverlay() => _bool('requestOverlay');
  static Future<void> requestAccessibility() => _bool('requestAccessibility');
  static Future<void> requestBattery() => _bool('requestBattery');
  static Future<void> openAppDetails() => _bool('openAppDetails');
  static Future<void> requestNotifications() => _bool('requestNotifications');

  // ---- Background service ----
  static Future<void> startService() => _bool('startService');

  // ---- Lock state ----
  static Future<bool> isNativeLocked() => _bool('isNativeLocked');
  static Future<bool> setNativeLocked(bool value) =>
      _bool('setNativeLocked', {'value': value});

  // ---- Pairing data ----
  static Future<void> saveDeviceToken(String token) =>
      _bool('saveDeviceToken', {'token': token, 'base_url': ApiConfig.baseUrl});

  static Future<bool> isPaired() => _bool('isPaired');
  static Future<void> setPaired(bool value) =>
      _bool('setPaired', {'value': value});

  static Future<String?> getInstallPairingCode() async {
    try {
      return await platform.invokeMethod<String>('getInstallPairingCode');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getDeviceName() async {
    try {
      return await platform.invokeMethod<String>('getDeviceName');
    } catch (_) {
      return null;
    }
  }
}
