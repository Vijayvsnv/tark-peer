import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  StreamSubscription? _sub;
  bool _cancelling = false;
  int _remaining = 90;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _timer?.cancel();
          _timeoutCancel();
        }
      });
    });
    _connect();
  }

  Future<void> _connect() async {
    final token = _auth.accessToken;
    debugPrint('[MatchingScreen] Token: ${token != null ? "present (${token.length} chars)" : "NULL"}');
    if (token == null) {
      if (mounted) context.go('/login');
      return;
    }
    debugPrint('[MatchingScreen] Calling MatchService.connect()...');
    try {
      await _matchService.connect(token);
      debugPrint('[MatchingScreen] connect() returned — setting up listener');
      _sub = _matchService.events.listen(_onEvent);
    } catch (e, st) {
      debugPrint('[MatchingScreen] Connection failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
        );
        context.go('/home');
      }
    }
  }

  void _onEvent(Map<String, dynamic> msg) {
    debugPrint('[MatchingScreen] Event received: $msg');
    if (!mounted) return;
    final type = msg['type'] as String?;
    if (type == 'matched') {
      debugPrint('[MatchingScreen] Match found! Going to /call');
      final event = MatchEvent.fromJson(msg);
      context.go('/call', extra: event);
    } else if (type == 'call_ended' || type == 'error') {
      debugPrint('[MatchingScreen] call_ended/error — going home. msg=$msg');
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

  Future<void> _timeoutCancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _matchService.sendCancel();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No partner found. Try again!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      context.go('/home');
    }
  }

  Color get _timerColor {
    if (_remaining > 60) return Colors.green;
    if (_remaining > 30) return Colors.amber;
    return Colors.red;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _matchService.dispose();
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
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(220, 220),
                      painter: _RingPainter(remaining: _remaining),
                    ),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [kCyan, kPrimary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimary.withOpacity(0.3),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.search, color: Colors.white, size: 44),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Finding a partner...',
                style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: _timerColor,
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
                child: Text('$_remaining'),
              ),
              const SizedBox(height: 6),
              Text(
                'seconds remaining',
                style: TextStyle(color: kTextSecondary.withOpacity(0.7), fontSize: 13),
              ),
              const SizedBox(height: 52),
              OutlinedButton.icon(
                onPressed: _cancelling ? null : _cancel,
                icon: const Icon(Icons.close, color: kDanger, size: 18),
                label: const Text('Cancel', style: TextStyle(color: kDanger, fontSize: 15, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kDanger, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int remaining;

  const _RingPainter({required this.remaining});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const strokeWidth = 13.0;
    const gapAngle = 0.09;
    final segmentSweep = (2 * pi / 3) - gapAngle;

    // Background arcs (grey)
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.withOpacity(0.15);

    for (int i = 0; i < 3; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + i * (2 * pi / 3) + gapAngle / 2,
        segmentSweep,
        false,
        bgPaint,
      );
    }

    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Green segment (90-60s) — segment 0
    final greenProgress = remaining > 60 ? (remaining - 60) / 30.0 : 0.0;
    if (greenProgress > 0) {
      fgPaint.color = Colors.green;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + gapAngle / 2,
        segmentSweep * greenProgress,
        false,
        fgPaint,
      );
    }

    // Yellow segment (60-30s) — segment 1
    final yellowProgress = remaining > 30 ? (min(remaining, 60) - 30) / 30.0 : 0.0;
    if (yellowProgress > 0) {
      fgPaint.color = Colors.amber;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + (2 * pi / 3) + gapAngle / 2,
        segmentSweep * yellowProgress,
        false,
        fgPaint,
      );
    }

    // Red segment (30-0s) — segment 2
    final redProgress = min(remaining, 30) / 30.0;
    if (redProgress > 0) {
      fgPaint.color = Colors.red;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + 2 * (2 * pi / 3) + gapAngle / 2,
        segmentSweep * redProgress,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining;
}
