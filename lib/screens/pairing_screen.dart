import 'dart:convert';

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
        _error = '৬ অক্ষরের pairing code দিন';
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
      final response = await http
          .post(
            Uri.parse(
              '${ApiConfig.baseUrl}/devices/${isFamilyInvite ? 'join-family' : 'pair'}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(
              isFamilyInvite
                  ? {
                      'family_invite': code,
                      'device_name': deviceName ?? 'Child phone',
                    }
                  : {'pairing_code': code},
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        setState(() {
          _error = 'ভুল বা মেয়াদোত্তীর্ণ pairing code';
        });
        return;
      }

      final data = jsonDecode(response.body);
      final token = data['device_token']?.toString();

      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'Server থেকে device token পাওয়া যায়নি';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_token', token);

      await DeviceAdminService.saveDeviceToken(token);
      await DeviceAdminService.setPaired(true);

      widget.onPaired();
    } catch (_) {
      setState(() {
        _error =
            'Server-এর সাথে সংযোগ করা যায়নি। Internet চালু আছে কিনা দেখুন';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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
              'Parent-এর device code বা family invite এখানে বসান।',
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
