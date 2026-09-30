import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'device_admin_service.dart';


class StatusService {
  static Timer? _timer;
  static const _setupActivatedKey = 'setup_activated';

  static final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);

  static void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkNow(),
    );
    checkNow();
  }

  static Future<void> checkNow() async {
    final locked = await DeviceAdminService.isNativeLocked();

    if (isLocked.value && !locked) {
      // Parent dashboard থেকে unlock হয়েছে: fullscreen mode বন্ধ করো
      await DeviceAdminService.setNativeLocked(false);
    }

    isLocked.value = locked;
  }

  static Future<bool> isSetupActivated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupActivatedKey) ?? false;
  }

  static Future<bool> activateAfterSetup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_setupActivatedKey) == true) return true;

      final token = prefs.getString('device_token');
      if (token == null || token.isEmpty) return false;

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/devices/activate-after-setup'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'device_token': token}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      if (data['success'] != true) return false;

      await prefs.setBool(_setupActivatedKey, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unlockWithCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('device_token');

      if (token == null || token.isEmpty) {
        return false;
      }

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/devices/unlock-with-code'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'device_token': token,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        return false;
      }

      await DeviceAdminService.setNativeLocked(false);
      isLocked.value = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}