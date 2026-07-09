import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../models/match_filter.dart';
import '../../services/ai_partner_service.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';
import '../../widgets/user_avatar.dart';

class MatchingScreen extends StatefulWidget {
  final MatchFilter? filter;
  const MatchingScreen({super.key, this.filter});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> with TickerProviderStateMixin {
  late MatchService _matchService;
  final _auth = AuthService();
  final _aiService = AiPartnerService();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _celebrateCtrl;
  late Animation<double> _celebrateScale;
  final _confettiCtrl = ConfettiController(duration: const Duration(milliseconds: 1200));

  StreamSubscription? _sub;
  bool _cancelling = false;
  bool _timedOut = false;
  bool _retrying = false;
  int _remaining = 90;
  Timer? _timer;
  bool _matched = false;
  MatchEvent? _matchedEvent;

  // AI partner offer state
  bool _aiOfferVisible = false;       // slide-up card shown at 45s
  bool _autoConnectActive = false;    // countdown card active (remaining <= 10)
  bool _autoConnectCancelled = false; // user cancelled the countdown
  bool _checkingQuota = false;
  int _aiQuotaRemaining = kAiDailyLimit; // assume available until checked

  @override
  void initState() {
    super.initState();
    _matchService = MatchService();
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
    _startTimer();
    _connect();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;

        // At 45s remaining: show AI offer card (first time only)
        if (_remaining == 45 && !_aiOfferVisible && !_matched) {
          _aiOfferVisible = true;
        }

        // At 10s remaining: check quota and start auto-connect countdown
        if (_remaining == 10 && !_autoConnectCancelled && !_matched) {
          _startAutoConnect();
        }

        // At 0: timeout
        if (_remaining <= 0) {
          _timer?.cancel();
          _onTimeout();
        }
      });
    });
  }

  Future<void> _startAutoConnect() async {
    if (_matched || _autoConnectCancelled) return;
    setState(() => _checkingQuota = true);
    try {
      final quota = await _aiService.getQuota();
      if (!mounted) return;
      setState(() {
        _aiQuotaRemaining = quota.remaining;
        _checkingQuota = false;
        // Only activate auto-connect if quota available and match not yet found
        if (quota.remaining > 0 && !_matched) {
          _autoConnectActive = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _checkingQuota = false);
    }
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
    } else if (type == 'restricted') {
      _timer?.cancel();
      _matchService.disconnect();
      final message = (msg['message'] as String?) ??
          'Your account is temporarily restricted due to reports.';
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Account Restricted',
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(message, style: const TextStyle(color: kTextSecondary)),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
    setState(() {
      _matchedEvent = event;
      _autoConnectActive = false; // cancel AI countdown — match wins
    });
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

  void _cancelAutoConnect() {
    setState(() {
      _autoConnectCancelled = true;
      _autoConnectActive = false;
    });
  }

  void _onTimeout() {
    if (_matched) return;
    if (_cancelling) return;

    _matchService.sendCancel();
    _matchService.disconnect();

    if (_autoConnectActive && !_autoConnectCancelled && _aiQuotaRemaining > 0) {
      // Auto-connect to Shivani
      context.go('/ai-call');
    } else {
      // Show plain timeout card
      setState(() {
        _cancelling = false;
        _timedOut = true;
      });
    }
  }

  Future<void> _goToAiCall() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _matchService.sendCancel();
    _matchService.disconnect();
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) context.go('/ai-call');
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    _sub?.cancel();
    _timer?.cancel();
    _matchService.dispose();
    _matchService = MatchService();
    setState(() {
      _timedOut = false;
      _remaining = 90;
      _cancelling = false;
      _matched = false;
      _matchedEvent = null;
      _retrying = false;
      _aiOfferVisible = false;
      _autoConnectActive = false;
      _autoConnectCancelled = false;
      _checkingQuota = false;
      _aiQuotaRemaining = kAiDailyLimit;
    });
    _startTimer();
    await _connect();
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
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF8B0000)),
                  const SizedBox(width: 5),
                  const Text(
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
          ),

          // AI offer slide-up card (at 45s, before auto-connect)
          if (_aiOfferVisible && !_autoConnectActive && !_autoConnectCancelled &&
              !_matched && !_timedOut && _remaining > 10)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _AiOfferCard(
                onTalkToShivani: _goToAiCall,
                onDismiss: () => setState(() => _aiOfferVisible = false),
              ),
            ),

          // Auto-connect countdown card (at 10s)
          if (_autoConnectActive && !_matched && !_timedOut)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _AutoConnectCard(
                countdown: _remaining,
                checking: _checkingQuota,
                onCancel: _cancelAutoConnect,
              ),
            ),

          if (_matchedEvent != null) _CelebrationOverlay(
            event: _matchedEvent!,
            scale: _celebrateScale,
            confetti: _confettiCtrl,
          ),
          if (_timedOut) _TimeoutCard(
            retrying: _retrying,
            onRetry: _retry,
            onCancel: () => context.go('/home'),
            onTalkToShivani: _goToAiCall,
          ),
        ],
      ),
    );
  }
}

// ─── AI offer card ───────────────────────────────────────────────────────────

class _AiOfferCard extends StatelessWidget {
  final VoidCallback onTalkToShivani;
  final VoidCallback onDismiss;

  const _AiOfferCard({required this.onTalkToShivani, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -4)),
        ],
        border: Border.all(color: kCyan.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: UserAvatar(imageUrl: kAiPartnerAvatar, name: kAiPartnerName, radius: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'No partner yet…',
                  style: TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Practice with Shivani (AI Partner) instead?',
                  style: TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onTalkToShivani,
            style: ElevatedButton.styleFrom(
              backgroundColor: kCyan,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              elevation: 0,
            ),
            child: const Text('Talk to\nShivani', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: kTextMuted),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ─── Auto-connect countdown card ─────────────────────────────────────────────

class _AutoConnectCard extends StatelessWidget {
  final int countdown;
  final bool checking;
  final VoidCallback onCancel;

  const _AutoConnectCard({required this.countdown, required this.checking, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, -4)),
        ],
        border: Border.all(color: kCyan.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        children: [
          ClipOval(
            child: UserAvatar(imageUrl: kAiPartnerAvatar, name: kAiPartnerName, radius: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: checking
                ? const Text('Checking availability…',
                    style: TextStyle(color: kTextSecondary, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No partner found —',
                        style: TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Connecting to Shivani (AI Partner) in ${countdown}s…',
                        style: const TextStyle(color: kTextSecondary, fontSize: 12),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: kDanger,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Existing widgets (unchanged) ────────────────────────────────────────────

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

class _TimeoutCard extends StatelessWidget {
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onTalkToShivani;

  const _TimeoutCard({
    required this.retrying,
    required this.onRetry,
    required this.onCancel,
    required this.onTalkToShivani,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: kSurface, shape: BoxShape.circle),
                  child: const Icon(Icons.search_off_rounded, size: 38, color: kTextMuted),
                ),
                const SizedBox(height: 18),
                const Text(
                  'No match found',
                  style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No one was available right now.\nTry again or practice with Shivani!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '⏰  Peak hours: Evening 8–9 PM',
                  style: TextStyle(color: kTextMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                // Shivani button — primary CTA
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: retrying ? null : onTalkToShivani,
                    icon: const Text('🤖', style: TextStyle(fontSize: 16)),
                    label: const Text(
                      'Talk to Shivani (AI Partner)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCyan,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: retrying ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kBorder, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: retrying ? null : onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: retrying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
    final radius = size.width / 2 - 10;
    final strokeWidth = 8.0;
    final bgPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    const total = 90.0;
    final fraction = (remaining / total).clamp(0.0, 1.0);
    Color arcColor;
    if (remaining > 60) {
      arcColor = Colors.green;
    } else if (remaining > 30) {
      arcColor = Colors.amber;
    } else {
      arcColor = Colors.red;
    }
    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * fraction,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining;
}
