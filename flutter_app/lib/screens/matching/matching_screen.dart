import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../models/match_filter.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';

class MatchingScreen extends StatefulWidget {
  final MatchFilter? filter;
  const MatchingScreen({super.key, this.filter});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> with TickerProviderStateMixin {
  final _matchService = MatchService();
  final _auth = AuthService();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _celebrateCtrl;
  late Animation<double> _celebrateScale;
  final _confettiCtrl = ConfettiController(duration: const Duration(milliseconds: 1200));
  StreamSubscription? _sub;
  bool _cancelling = false;
  int _remaining = 90;
  Timer? _timer;
  bool _matched = false;
  MatchEvent? _matchedEvent;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _celebrateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _celebrateScale = CurvedAnimation(
      parent: _celebrateCtrl,
      curve: Curves.elasticOut,
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
      await _matchService.connect(token, filter: widget.filter);
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
      debugPrint('[MatchingScreen] Match found! Celebrating...');
      final event = MatchEvent.fromJson(msg);
      _celebrateAndNavigate(event);
    } else if (type == 'call_ended' || type == 'error') {
      debugPrint('[MatchingScreen] call_ended/error — going home. msg=$msg');
      context.go('/home');
    }
  }

  Future<void> _celebrateAndNavigate(MatchEvent event) async {
    if (_matched) return;
    _matched = true;
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _matchedEvent = event);
    _celebrateCtrl.forward(from: 0);
    _confettiCtrl.play();
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) context.go('/call', extra: event);
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
    _celebrateCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Stack(
        children: [
          SafeArea(
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
              if (widget.filter != null && widget.filter!.hasAnyFilter) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.filter!.gender != null)
                      _FilterChip(widget.filter!.gender!),
                    if (widget.filter!.ageRange != null)
                      _FilterChip(widget.filter!.ageRange!),
                    if (widget.filter!.minRating != null || widget.filter!.maxRating != null)
                      _FilterChip(
                        '${widget.filter!.minRating?.toStringAsFixed(0) ?? 'Any'}★'
                        ' – '
                        '${widget.filter!.maxRating?.toStringAsFixed(0) ?? 'Any'}★',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
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
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF8B0000)),
                  SizedBox(width: 5),
                  Text(
                    'Non-English speakers will be banned',
                    style: TextStyle(
                      color: Color(0xFF8B0000),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _cancelling || _matched ? null : _cancel,
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
            if (_matchedEvent != null) _CelebrationOverlay(
              event: _matchedEvent!,
              scale: _celebrateScale,
              confetti: _confettiCtrl,
            ),
        ],
      ),
    );
  }
}

class _CelebrationOverlay extends StatelessWidget {
  final MatchEvent event;
  final Animation<double> scale;
  final ConfettiController confetti;

  const _CelebrationOverlay({
    required this.event,
    required this.scale,
    required this.confetti,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: confetti,
                blastDirection: pi / 2,
                blastDirectionality: BlastDirectionality.explosive,
                maxBlastForce: 22,
                minBlastForce: 8,
                emissionFrequency: 0.08,
                numberOfParticles: 26,
                gravity: 0.28,
                shouldLoop: false,
                colors: const [
                  Color(0xFFF97316),
                  Color(0xFF60A5FA),
                  Color(0xFF34D399),
                  Color(0xFF8B5CF6),
                  Color(0xFFFACC15),
                ],
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: scale,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          color: kSuccess,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Partner Found!',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Connecting you with ${event.partner.name}…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  const _FilterChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withOpacity(0.3)),
      ),
      child: Text(label, style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
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

    // Only the active segment is colored — others stay grey.
    // Green (90→60s) → Yellow (60→30s) → Red (30→0s)
    if (remaining > 60) {
      fgPaint.color = Colors.green;
      final progress = (remaining - 60) / 30.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + gapAngle / 2,
        segmentSweep * progress,
        false,
        fgPaint,
      );
    } else if (remaining > 30) {
      fgPaint.color = Colors.amber;
      final progress = (remaining - 30) / 30.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + (2 * pi / 3) + gapAngle / 2,
        segmentSweep * progress,
        false,
        fgPaint,
      );
    } else if (remaining > 0) {
      fgPaint.color = Colors.red;
      final progress = remaining / 30.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + 2 * (2 * pi / 3) + gapAngle / 2,
        segmentSweep * progress,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining;
}
