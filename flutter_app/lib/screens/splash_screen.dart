import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../core/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      context.go('/login');
      return;
    }

    try {
      final profile = await ProfileService().getMyProfile();
      if (!mounted) return;
      if (profile == null || !profile.isProfileComplete) {
        context.go('/setup');
      } else {
        context.go('/home');
      }
    } catch (_) {
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/Tark-pear-logo-change.png',
              width: 340,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            const Text(
              'Random voice conversations',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: kPrimary),
          ],
        ),
      ),
    );
  }
}
