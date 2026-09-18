import 'package:flutter/material.dart';

void main() {
  runApp(const HasanApp());
}

class HasanApp extends StatelessWidget {
  const HasanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حسن',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08090C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3DCF9A),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'حسن',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'اتصال امن، یک لمس',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 48),
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF3DCF9A), width: 3),
              ),
              child: const Center(
                child: Icon(
                  Icons.power_settings_new,
                  color: Color(0xFF3DCF9A),
                  size: 64,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
