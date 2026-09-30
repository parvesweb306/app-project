import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/lock_overlay_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/setup_screen.dart';

import 'services/device_admin_service.dart';
import 'services/status_service.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final paired = await DeviceAdminService.isPaired();
  final nativeLocked = await DeviceAdminService.isNativeLocked();
  final setupOk = await _isSetupComplete();

  runApp(
    ParentalControlApp(
      initiallyPaired: paired,
      initiallyLocked: nativeLocked,
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
  State<ParentalControlApp> createState() =>
      _ParentalControlAppState();
}

class _ParentalControlAppState
    extends State<ParentalControlApp>
    with WidgetsBindingObserver {
  late bool _paired;
  late bool _locked;
  late bool _setupOk;
  bool _activationInProgress = false;
  bool _activationPending = false;
  String? _activationError;

  @override
  void initState() {
    super.initState();

    _paired = widget.initiallyPaired;
    _locked = widget.initiallyLocked;
    _setupOk = widget.initiallySetupOk;

    WidgetsBinding.instance.addObserver(this);

    StatusService.isLocked.addListener(_lockStateChanged);
    StatusService.startPolling();

    if (_paired) {
      DeviceAdminService.startService();
     
    }

    _activateIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    StatusService.isLocked.removeListener(_lockStateChanged);

    StatusService.stopPolling();
   

    super.dispose();
  }

  void _lockStateChanged() {
    if (!mounted) return;

    setState(() {
      _locked = StatusService.isLocked.value;
    });
  }

  Future<void> _activateIfNeeded() async {
    if (!_paired || !_setupOk || _activationInProgress) return;

    _activationInProgress = true;
    try {
      if (await StatusService.isSetupActivated()) return;

      if (mounted) {
        setState(() {
          _activationPending = true;
          _activationError = null;
        });
      }

      final activated = await StatusService.activateAfterSetup();
      if (!activated) {
        if (mounted) {
          setState(() {
            _activationError = 'সার্ভারে activation হয়নি। Internet connection দেখে আবার চেষ্টা করুন।';
          });
        }
        return;
      }

      await DeviceAdminService.setNativeLocked(true);
      await DeviceAdminService.startService();

      final locked = await DeviceAdminService.isNativeLocked();
      if (!mounted) return;

      setState(() {
        _locked = locked;
        _activationPending = false;
        _activationError = null;
      });
      StatusService.checkNow();
    } finally {
      _activationInProgress = false;
    }
  }

Future<void> _onPaired() async {
  await DeviceAdminService.setPaired(true);

  await DeviceAdminService.startService();

  if (!mounted) return;

  setState(() {
    _paired = true;
  });

  _activateIfNeeded();
}

  Future<void> _recheckSetup() async {
    final ok = await _isSetupComplete();

    if (!mounted) return;

    setState(() {
      _setupOk = ok;
    });

    if (ok && _paired) _activateIfNeeded();
  }

@override
void didChangeAppLifecycleState(
  AppLifecycleState state,
) {
  if (state == AppLifecycleState.resumed && _paired) {
    StatusService.checkNow();
    _recheckSetup();
  }
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Child Guard',

      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor:
            const Color(0xFFF7F8FC),
      ),

      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // প্রথমে pairing করতে হবে।
    if (!_paired) {
      return PairingScreen(
        onPaired: _onPaired,
      );
    }

    // Permission শেষ হওয়ার পর automatic lock হলে
    // সরাসরি LockOverlayScreen দেখাবে।
    if (_locked) {
      return const LockOverlayScreen();
    }

    if (_activationPending) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_sync_rounded, size: 44),
                  const SizedBox(height: 16),
                  const Text(
                    'Parent অনুমোদন যাচাই হচ্ছে',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  if (_activationError != null) ...[
                    const SizedBox(height: 12),
                    Text(_activationError!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _activationInProgress ? null : _activateIfNeeded,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('আবার চেষ্টা করুন'),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Pairing হয়েছে কিন্তু permission এখনো শেষ হয়নি।
    if (!_setupOk) {
      return SetupScreen(
        onDone: _recheckSetup,
      );
    }

    return const HomeScreen();
  }
}
