import 'package:flutter/material.dart';

void main() => runApp(const ToolInventoryApp());

const kAmber = Color(0xFFF5A623);
const kBg = Color(0xFF0B0C0E);

class ToolInventoryApp extends StatelessWidget {
  const ToolInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tool Inventory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAmber, surface: kBg),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Tool Inventory',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                Text(
                  'Pipeline test build. If you can read this on your phone, '
                  'the download and install path works.',
                  style: TextStyle(fontSize: 16, color: Color(0xFFA3A9B1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
