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

  static final RegExp _codePattern = RegExp(r'^(?:[A-Z0-9]{6}|[A-Z0-9]{32})$');

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
    if (code == null) {
      await Future.delayed(const Duration(milliseconds: 700));
      code = await _readClipboardCode();
    }

    if (!mounted) return;

    if (code != null) {
      _codeController.text = code;
      setState(() {
        _autoChecking = false;
      });
      await _pair();
      return;
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
        _error = 'Clipboard এ কোনো pairing code পাওয়া যায়নি';
      });
    }
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim().toUpperCase();

    if (!_codePattern.hasMatch(code)) {
      setState(() {
        _error = '৬ অক্ষরের pairing code অথবা family invite দিন';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isFamilyInvite = code.length == 32;
      final deviceName = await DeviceAdminService.getDeviceName();
      final requestBody = isFamilyInvite
          ? {
              'family_invite': code,
              'installation_id': await _getInstallationId(),
              'device_name': deviceName ?? 'Child phone',
            }
          : {'pairing_code': code};
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
          .timeout(const Duration(seconds: 10));

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

      if (!mounted) return;
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

      widget.onPaired();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Server response দিতে দেরি হচ্ছে। আবার চেষ্টা করুন।';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _error = 'Internet connection নেই। সংযোগ করে আবার চেষ্টা করুন।';
      });
    } on http.ClientException {
      if (!mounted) return;
      setState(() {
        _error = 'Server-এর সাথে সংযোগ করা যায়নি। পরে আবার চেষ্টা করুন।';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _error = 'Server-এর response বোঝা যায়নি। পরে আবার চেষ্টা করুন।';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'এই ফোনের pairing তথ্য পড়া যায়নি।';
      });
    } on Exception catch (error) {
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
              Text(
                'Parent এর সাথে সংযোগ হচ্ছে...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Child Device Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Set up Child Guard',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Play Store-এর family link দিয়ে install করলে app নিজে connect হবে। '
              'তা না হলে parent-এর pairing code বা family invite দিন।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 28),
            const Text(
              'Pairing Code / Family Invite',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              maxLength: 32,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                hintText: 'Code বা 32-character invite',
                counterText: '',
                filled: true,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _paste,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _loading ? null : _pair,
                child: const Text(
                  'Connect Device',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
