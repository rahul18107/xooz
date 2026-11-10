import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const XoozApp());
}

class XoozApp extends StatelessWidget {
  const XoozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xooz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          background: Color(0xFF0A0A0A),
          surface: Color(0xFF1A1512),
          primary: Color(0xFFE8DFD0),
          secondary: Color(0xFFC8B89A),
        ),
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}