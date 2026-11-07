
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/device_admin_service.dart';

class PairingScreen extends StatefulWidget {
  final VoidCallback onPaired;

  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _codeController = TextEditingController();

  bool _loading = false;
  bool _autoChecking = true;
  String? _error;

  static final RegExp _codePattern =
      RegExp(r'^(?:[A-Z0-9]{6}|[A-Z0-9]{32})$');

  @override
  void initState() {
    super.initState();
    _tryClipboardAndPair();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<String?> _readClipboardCode() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = (data?.text ?? '').trim().toUpperCase();

      if (_codePattern.hasMatch(text)) {
        return text;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _tryClipboardAndPair() async {
    var code = await DeviceAdminService.getInstallPairingCode();

    if (code == null) {
      await Future.delayed(const Duration(milliseconds: 500));
      code = await _readClipboardCode();
    }

    if (!mounted) return;

    if (code != null) {
      _codeController.text = code;
    }

    setState(() {
      _autoChecking = false;
    });
  }

  Future<void> _paste() async {
    final code = await _readClipboardCode();

    if (!mounted) return;

    if (code != null) {
      setState(() {
        _codeController.text = code;
        _error = null;
      });
    } else {
      setState(() {
        _error = 'Clipboard এ কোনো valid Family Code পাওয়া যায়নি।';
      });
    }
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim().toUpperCase();

    if (!_codePattern.hasMatch(code)) {
      setState(() {
        _error = '৬ অক্ষরের Pairing Code অথবা ৩২ অক্ষরের Family Code দিন।';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isFamilyInvite = code.length == 32;

      final telemetry =
          await DeviceAdminService.getDeviceTelemetry();

      final deviceName =
          telemetry['device_name'] ??
          await DeviceAdminService.getDeviceName() ??
          'Child phone';

      final requestBody = isFamilyInvite
          ? {
              'family_invite': code,
              'installation_id': await _getInstallationId(),
              'device_name': deviceName,
              'manufacturer': telemetry['manufacturer'],
              'model': telemetry['model'],
              'android_version': telemetry['android_version'],
              'battery_level': telemetry['battery_level'],
            }
          : {
              'pairing_code': code,
            };

      final response = await http
          .post(
            Uri.parse(
              '${ApiConfig.baseUrl}/devices/${isFamilyInvite ? 'enroll-family' : 'pair'}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 20));

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected pairing response.');
      }

      if (response.statusCode != 200) {
        if (!mounted) return;

        setState(() {
          _error = decoded['error']?.toString() ??
              decoded['message']?.toString() ??
              'Pairing করা যায়নি (${response.statusCode})';
        });
        return;
      }

      final token = decoded['device_token']?.toString();

      if (token == null || token.isEmpty) {
        throw const FormatException(
          'Server response did not contain a device token.',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_token', token);

      if (!await DeviceAdminService.saveDeviceToken(token)) {
        throw PlatformException(
          code: 'DEVICE_TOKEN_SAVE_FAILED',
          message: 'এই ফোনে device token সংরক্ষণ করা যায়নি।',
        );
      }

      if (!await DeviceAdminService.setPaired(true)) {
        throw PlatformException(
          code: 'PAIRING_STATE_SAVE_FAILED',
          message: 'এই ফোনে paired state সংরক্ষণ করা যায়নি।',
        );
      }

      if (!mounted) return;
      widget.onPaired();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Server response দিতে দেরি হচ্ছে। আবার চেষ্টা করুন।';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _error = 'Internet connection নেই। আবার চেষ্টা করুন।';
      });
    } on http.ClientException {
      if (!mounted) return;
      setState(() {
        _error = 'Server-এর সাথে সংযোগ করা যায়নি।';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _error = 'Server-এর response বোঝা যায়নি।';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'Pairing তথ্য সংরক্ষণ করা যায়নি।';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Pairing ব্যর্থ হয়েছে: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<String> _getInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existingId = prefs.getString('installation_id');

    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }

    final bytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );

    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    final installationId = [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');

    await prefs.setString('installation_id', installationId);

    return installationId;
  }

  @override
  Widget build(BuildContext context) {
    if (_autoChecking || (_loading && _error == null)) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('Checking Family Connection...'),
            ],
          ),
        ),
      );
    }

    final hasCode = _codeController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Guard Setup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),

            const Icon(
              Icons.shield_rounded,
              size: 75,
              color: Colors.indigo,
            ),

            const SizedBox(height: 20),

            const Text(
              'Connect to Family',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Enter the Family Invite Code provided by your Parent '
              'to connect this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 25),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device information sharing',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text('• Device model and Android version'),
                  Text('• Battery level and connection details'),
                  Text('• Public IP and approximate IP location'),
                  Text('• Device lock and unlock status'),
                  SizedBox(height: 12),
                  Text(
                    'The linked Parent can view device information '
                    'and use the enabled Child Guard management features.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              'Family Invite / Pairing Code',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 9),

            TextField(
              controller: _codeController,
              enabled: !_loading,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 32,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[a-zA-Z0-9]'),
                ),
                UpperCaseTextFormatter(),
              ],
              onChanged: (_) {
                setState(() {
                  _error = null;
                });
              },
              decoration: InputDecoration(
                hintText: 'Paste your 32-character Family Code',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste Code',
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'You can paste the Family Code manually if the installation '
              'link does not open the app.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],

            const SizedBox(height: 22),

            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _loading || !hasCode ? null : _pair,
                child: _loading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text(
                        'Agree & Connect Device',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
