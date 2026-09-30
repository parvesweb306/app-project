import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Child Device',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_open_rounded,
                    size: 58,
                    color: Colors.green.shade600,
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  'Device is unlocked',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'This device is connected to the parent account and can be locked remotely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 30),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_done,
                        color: Colors.indigo,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Connected',
                        style: TextStyle(
                          color: Colors.indigo,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
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