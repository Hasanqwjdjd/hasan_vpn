import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

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
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const HomeScreen(),
    );
  }
}
