import 'package:flutter/material.dart';

const Color kPrimary = Color(0xFF7C3AED);
const Color kPrimaryLight = Color(0xFFEDE9FE);
const Color kBackground = Color(0xFF0F0A1E);
const Color kSurface = Color(0xFF1A1030);
const Color kTextPrimary = Colors.white;
const Color kTextSecondary = Color(0xFFB8B0CC);

ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: kPrimary,
  scaffoldBackgroundColor: kBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.dark,
    background: kBackground,
    surface: kSurface,
  ),
  fontFamily: 'Inter',
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF3D2F6E)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF3D2F6E)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimary, width: 2),
    ),
    labelStyle: const TextStyle(color: kTextSecondary),
    hintStyle: const TextStyle(color: kTextSecondary),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBackground,
    foregroundColor: kTextPrimary,
    elevation: 0,
  ),
);
