import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> with TickerProviderStateMixin {
  final _matchService = MatchService();
  final _auth = AuthService();
  late AnimationController _spinCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  StreamSubscription? _sub;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _connect();
  }

  Future<void> _connect() async {
    final token = _auth.accessToken;
    if (token == null) {
      if (mounted) context.go('/login');
      return;
    }
    try {
      await _matchService.connect(token);
      _sub = _matchService.events.listen(_onEvent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
        );
        context.go('/home');
      }
    }
  }

  void _onEvent(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;
    if (type == 'matched') {
      final event = MatchEvent.fromJson(msg);
      context.go('/call', extra: event);
    } else if (type == 'call_ended' || type == 'error') {
      context.go('/home');
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _matchService.sendCancel();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _matchService.dispose();
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kPrimary.withOpacity(0.3), width: 2),
                      ),
                    ),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kPrimary.withOpacity(0.5), width: 2),
                      ),
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimary,
                      ),
                      child: const Icon(Icons.search, color: Colors.white, size: 36),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Finding a partner...',
                style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please wait while we match you',
                style: TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _spinCtrl,
                builder: (_, __) {
                  final dots = '.' * ((_spinCtrl.value * 3).floor() + 1);
                  return Text(dots, style: const TextStyle(color: kPrimary, fontSize: 24));
                },
              ),
              const SizedBox(height: 60),
              TextButton.icon(
                onPressed: _cancelling ? null : _cancel,
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text('Cancel', style: TextStyle(color: Colors.red, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
