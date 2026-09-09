import 'package:flutter/material.dart';
import 'core/tokens.dart';
import 'screens/welcome_screen.dart';

void main() => runApp(const FlovaApp());

class FlovaApp extends StatelessWidget {
  const FlovaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flova',
        debugShowCheckedModeBanner: false,
        theme: flovaTheme(),
        home: const WelcomeScreen(),
      );
}