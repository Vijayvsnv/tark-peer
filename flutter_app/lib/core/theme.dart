import 'package:flutter/material.dart';

// ── Brand palette (sourced from logo) ────────────────────────────────────────
// Logo gradients:
//   T letter: #F05423 → #FCC211  (orange → gold)
//   P letter: #416CB4 → #39C6F4  (steel blue → cyan)
//   Wordmark: "Tark" = #102235 (dark navy)  •  "Peer" = #4171B8 (steel blue)

const Color kPrimary       = Color(0xFF4171B8); // steel blue — primary interactive
const Color kPrimaryDeep   = Color(0xFF102235); // dark navy — headings, immersive
const Color kPrimaryLight  = Color(0xFFE8EEF8); // light tint for chips, hover

const Color kAccent        = Color(0xFFF05423); // orange — main CTA
const Color kAccentSoft    = Color(0xFFFCC211); // gold — CTA gradient end
const Color kCyan          = Color(0xFF39C6F4); // sky — micro accents, glows

const Color kSuccess       = Color(0xFF22C55E); // online, friends accepted
const Color kDanger        = Color(0xFFEF4444); // end call, errors

const Color kBackground    = Color(0xFFFFFFFF); // pure white scaffold
const Color kSurface       = Color(0xFFF4F6FB); // very light lavender wash for cards
const Color kSurfaceAlt    = Color(0xFFEEF1F8); // slightly deeper card bg
const Color kBorder        = Color(0xFFE5E7EB); // subtle dividers

const Color kTextPrimary   = Color(0xFF0B1422); // near-black for headings
const Color kTextSecondary = Color(0xFF6B7280); // slate gray for body
const Color kTextMuted     = Color(0xFF9CA3AF); // hints, timestamps

// Immersive dark surfaces — used ONLY in call screen for focus
const Color kCallBgTop     = Color(0xFF0B1422);
const Color kCallBgBottom  = Color(0xFF15243B);

ThemeData appTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: kPrimary,
  scaffoldBackgroundColor: kBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.light,
    primary: kPrimary,
    secondary: kAccent,
    background: kBackground,
    surface: kSurface,
    error: kDanger,
    onBackground: kTextPrimary,
    onSurface: kTextPrimary,
  ),
  fontFamily: 'Inter',
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      elevation: 0,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kPrimary, width: 2),
    ),
    labelStyle: const TextStyle(color: kTextSecondary),
    hintStyle: const TextStyle(color: kTextMuted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBackground,
    foregroundColor: kTextPrimary,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: kTextPrimary),
    titleTextStyle: TextStyle(
      color: kTextPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: kBackground,
    selectedItemColor: kPrimary,
    unselectedItemColor: kTextMuted,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
  dividerTheme: const DividerThemeData(color: kBorder, thickness: 1, space: 1),
);
