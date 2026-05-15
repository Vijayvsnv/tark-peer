import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/user_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _profileService = ProfileService();
  UserProfile? _profile;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _profileService.getMyProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: _profile?.name ?? 'U',
              imageUrl: _profile?.avatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Text(
              _profile?.name ?? 'Loading...',
              style: const TextStyle(color: kTextPrimary, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: kTextSecondary),
            onPressed: () async {
              await _auth.signOut();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.mic, color: kPrimary, size: 32),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tark Peer',
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Random voice conversations',
              style: TextStyle(color: kTextSecondary, fontSize: 16),
            ),
            const SizedBox(height: 60),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Transform.scale(
                scale: _pulse.value,
                child: child,
              ),
              child: _PulseButton(
                onTap: () => context.go('/matching'),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Tap to find a random partner',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            if (_profile != null) ...[
              const SizedBox(height: 40),
              Text(
                'Total calls: ${_profile!.totalCalls}',
                style: const TextStyle(color: kTextSecondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PulseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PulseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFF9F67FF), kPrimary],
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimary.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, color: Colors.white, size: 48),
            SizedBox(height: 8),
            Text(
              'Find\nPartner',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
