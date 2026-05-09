import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF0A0A0A);
  static const card = Color(0xFF111111);
  static const line = Color(0xFF1A1A1A);
  static const lineStrong = Color(0xFF2A2A2A);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0x8CFFFFFF);
  static const faint = Color(0x59FFFFFF);
}

class AppTextStyles {
  static TextStyle display(double size, {FontWeight weight = FontWeight.w800}) =>
      GoogleFonts.syne(fontSize: size, fontWeight: weight, letterSpacing: -0.02 * size, color: AppColors.text, height: 1.0);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color ?? AppColors.text);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color ?? AppColors.text);

  static TextStyle eyebrow = GoogleFonts.dmSans(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.22 * 10,
    color: AppColors.muted,
  );

  static TextStyle chip = GoogleFonts.dmSans(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.08 * 11,
    color: AppColors.text,
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.text,
      surface: AppColors.bg,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 0,
    ),
  );
}
