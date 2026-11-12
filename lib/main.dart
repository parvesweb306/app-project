import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/pairing_screen.dart';
import 'screens/setup_screen.dart';
import 'services/device_admin_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final paired = await DeviceAdminService.isPaired();
  final locked = await DeviceAdminService.isNativeLocked();
  final setupOk = await _isSetupComplete();

  runApp(
    ParentalControlApp(
      initiallyPaired: paired,
      initiallyLocked: locked,
      initiallySetupOk: setupOk,
    ),
  );
}

Future<bool> _isSetupComplete() async {
  final results = await Future.wait([
    DeviceAdminService.isAdminActive(),
    DeviceAdminService.isOverlayGranted(),
    DeviceAdminService.isAccessibilityEnabled(),
    DeviceAdminService.isBatteryIgnored(),
  ]);

  return results.every((e) => e);
}

const _channel = MethodChannel('device_admin_channel');

Future<String?> _getDeviceToken() =>
    _channel.invokeMethod<String>('getDeviceToken');

Future<Map<String, dynamic>?> _getTelemetry() async {
  try {
    final map =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceTelemetry');
    return map?.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> _postJson(
  String path,
  Map<String, dynamic> body,
) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) return null;
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client?.close();
  }
}

class ParentalControlApp extends StatefulWidget {
  final bool initiallyPaired;
  final bool initiallyLocked;
  final bool initiallySetupOk;

  const ParentalControlApp({
    super.key,
    required this.initiallyPaired,
    required this.initiallyLocked,
    required this.initiallySetupOk,
  });

  @override
  State<ParentalControlApp> createState() => _ParentalControlAppState();
}

class _ParentalControlAppState extends State<ParentalControlApp>
    with WidgetsBindingObserver {
  late bool _paired;
  late bool _locked;
  late bool _setupOk;
  bool _allowing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();

    _paired = widget.initiallyPaired;
    _locked = widget.initiallyLocked;
    _setupOk = widget.initiallySetupOk;

    WidgetsBinding.instance.addObserver(this);

    if (_paired) {
      DeviceAdminService.startService();
    }

    // Native lock state নিয়মিত check
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final native = await DeviceAdminService.isNativeLocked();
      if (native && mounted && !_locked) {
        setState(() => _locked = true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onPaired() async {
    await DeviceAdminService.setPaired(true);
    await DeviceAdminService.startService();

    if (!mounted) return;
    setState(() => _paired = true);
  }

  Future<void> _recheckSetup() async {
    final ok = await _isSetupComplete();
    if (!mounted) return;
    setState(() => _setupOk = ok);
  }

  // ---------- ALLOW বাটন → Lifetime Hard Lock ----------
  Future<void> _onAllow() async {
    if (_allowing || _locked) return;
    setState(() => _allowing = true);

    // ১. Native hard lock + ৯-ডিজিটের code তৈরি
    final code = await _channel.invokeMethod<String>('hardLock');

    // ২. Code + device details → Parent dashboard
    if (code != null) {
      final token = await _getDeviceToken();
      final telemetry = await _getTelemetry();

      if (token != null) {
        await _postJson('/devices/hard-lock', {
          'device_token': token,
          'unlock_code': code,
          'device_name': telemetry?['device_name'],
          'battery_level': telemetry?['battery_level'],
          'android_version': telemetry?['android_version'],
        });
      }
    }

    final locked = await DeviceAdminService.isNativeLocked();
    if (!mounted) return;
    setState(() {
      _allowing = false;
      _locked = locked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Child Guard',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // প্রথমে pairing
    if (!_paired) {
      return PairingScreen(onPaired: _onPaired);
    }

    // Locked → শুধু ৯-ডিজিটের Code লেখার জায়গা
    if (_locked) {
      return HardLockScreen(
        onUnlocked: () => setState(() => _locked = false),
      );
    }

    // একবার setup (permission)
    if (!_setupOk) {
      return SetupScreen(onDone: _recheckSetup);
    }

    // Setup শেষ → শুধু ১টা ALLOW বাটন
    return AllowScreen(
      allowing: _allowing,
      onAllow: _onAllow,
    );
  }
}

// ---------- ALLOW SCREEN ----------
class AllowScreen extends StatelessWidget {
  final bool allowing;
  final VoidCallback onAllow;

  const AllowScreen({super.key, required this.allowing, required this.onAllow});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_rounded,
                    size: 80, color: Colors.indigo),
                const SizedBox(height: 24),
                const Text(
                  'এই Device Protected করতে Allow চাপুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: allowing ? null : onAllow,
                    icon: allowing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_rounded),
                    label: const Text(
                      'ALLOW',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- LOCKED SCREEN (শুধু Code দিলেই খুলবে) ----------
class HardLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const HardLockScreen({super.key, required this.onUnlocked});

  @override
  State<HardLockScreen> createState() => _HardLockScreenState();
}

class _HardLockScreenState extends State<HardLockScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _tryUnlock() async {
    final code = _controller.text.trim();

    if (code.length != 9) {
      setState(() => _error = '৯ ডিজিটের কোড দিন');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    var unlocked = false;

    // ১. Server দিয়ে verify (online হলে dashboard sync হবে)
    final token = await _getDeviceToken();
    Map<String, dynamic>? serverResponse;

    if (token != null) {
      serverResponse = await _postJson('/devices/unlock-with-lifetime-code', {
        'device_token': token,
        'code': code,
      });
    }

    if (serverResponse == null) {
      // ২. Internet নেই → Local hash verify
      unlocked = await _channel
              .invokeMethod<bool>('unlockWithCode', {'code': code}) ??
          false;
    } else if (serverResponse['success'] == true) {
      await _channel.invokeMethod<bool>('forceUnlock');
      unlocked = true;
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (unlocked) {
      _controller.clear();
      widget.onUnlocked();
    } else {
      setState(() => _error = 'ভুল কোড। সঠিক কোড Parent-এর কাছে আছে।');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101322),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 72, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Device Protected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          letterSpacing: 8),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '— — — — — — — — —',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 250,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _tryUnlock,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('UNLOCK'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
