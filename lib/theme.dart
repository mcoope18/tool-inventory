import 'package:flutter/material.dart';

const kBg = Color(0xFF0B0C0E);
const kSurface = Color(0xFF15171A);
const kCard = Color(0xFF1C1F23);
const kTile = Color(0xFF22262B);
const kLine = Color(0xFF2A2E34);
const kText = Color(0xFFF3F4F6);
const kText2 = Color(0xFFA3A9B1);
const kAmber = Color(0xFFF5A623);
const kBlue = Color(0xFF7DB8FF);

ThemeData appTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(primary: kAmber, onPrimary: Colors.black, surface: kBg, secondary: kAmber),
    appBarTheme: const AppBarTheme(backgroundColor: kBg, surfaceTintColor: Colors.transparent, elevation: 0),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kText,
      contentTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: kLine,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF111316),
      indicatorColor: kAmber.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ),
  );
}

InputDecoration inputDeco(String hint, {Widget? prefix, Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8B929B)),
      filled: true,
      fillColor: kCard,
      prefixIcon: prefix,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kAmber)),
    );

ButtonStyle amberBtn() => FilledButton.styleFrom(
      backgroundColor: kAmber,
      foregroundColor: Colors.black,
      minimumSize: const Size(44, 48),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

ButtonStyle ghostBtn() => OutlinedButton.styleFrom(
      foregroundColor: kText,
      side: const BorderSide(color: kLine),
      minimumSize: const Size(44, 48),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

const sectionLabel = TextStyle(fontSize: 12, color: kText2, fontWeight: FontWeight.w600, letterSpacing: 0.7);

IconData catIcon(String cat) {
  switch (cat) {
    case 'cutter':
      return Icons.hardware_rounded;
    case 'hand':
      return Icons.build_rounded;
    case 'power':
      return Icons.electrical_services_rounded;
    case 'measure':
      return Icons.straighten_rounded;
    default:
      return Icons.category_rounded;
  }
}

Color catColor(String cat) {
  switch (cat) {
    case 'cutter':
      return kBlue;
    case 'hand':
      return const Color(0xFFF5B451);
    case 'power':
      return const Color(0xFFC9A2FF);
    case 'measure':
      return const Color(0xFF6EE7B7);
    default:
      return kText2;
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}
