import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/ai_partner_service.dart';
import '../../services/ai_voice_controller.dart';
import '../../services/analytics_service.dart';
import '../../services/review_service.dart';
import '../../widgets/user_avatar.dart';

class AiCallScreen extends StatefulWidget {
  final String? source;
  const AiCallScreen({super.key, this.source});

  @override
  State<AiCallScreen> createState() => _AiCallScreenState();
}

class _AiCallScreenState extends State<AiCallScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _service = AiPartnerService();

  AiVoiceController? _voice;
  String? _sessionId;
  int _maxSeconds = kAiMaxCallSeconds;
  int _elapsed = 0;
  Timer? _timer;

  // Full transcript for feedback (never trimmed)
  final _transcript = <Map<String, String>>[];

  bool _starting = true;
  bool _micMuted = false;
  String? _retryText;   // last user text if /chat failed
  int _consecutiveFails = 0;

  // Pulse animation for speaking indicator
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause voice I/O when app is backgrounded — resume on foreground
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _voice?.pauseListening();
    } else if (state == AppLifecycleState.resumed) {
      if (_voice?.state.value == AiVoiceState.idle && _sessionId != null) {
        _voice?.resumeListening();
      }
    }
  }

  Future<void> _start() async {
    // 1. Mic permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        _showError('Microphone permission required for AI practice.');
        context.go('/home');
      }
      return;
    }

    // 2. Start backend session
    AiSession session;
    try {
      session = await _service.startSession();
    } on AiDailyLimitException {
      if (mounted) _showDailyLimitDialog();
      return;
    } on AiUnavailableException {
      if (mounted) {
        _showError('AI partner is currently unavailable. Try again later.');
        context.go('/home');
      }
      return;
    } catch (_) {
      if (mounted) {
        _showError('Could not connect to AI partner. Check your connection.');
        context.go('/home');
      }
      return;
    }

    _sessionId = session.sessionId;
    _maxSeconds = session.maxSeconds;
    AnalyticsService.instance.logAiSessionStarted(widget.source ?? 'home_button');

    // 3. Init voice controller
    _voice = AiVoiceController(
      onUserTurn: _handleUserTurn,
      onUserSilent: _handleUserSilent,
      onError: (msg) {
        if (mounted) setState(() {});
        // Don't block session on STT error — show state only
      },
    );
    await _voice!.init();

    if (!mounted) return;
    setState(() => _starting = false);

    // 4. Start elapsed timer
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= _maxSeconds) _endCall(autoEnd: true);
      });
    });

    // 5. Speak fixed greeting (no API call needed)
    await _voice!.speak(
      "Hi! I'm Shivani, your AI practice partner. What's your name?",
    );
  }

  Future<void> _handleUserTurn(String userText) async {
    if (_sessionId == null) return;
    _retryText = userText;
    _transcript.add({'role': 'user', 'text': userText});

    // Build trimmed history for API (last 8 pairs = 16 turns)
    final history = _buildHistory();

    final reply = await _service.chat(_sessionId!, userText, history);

    if (!mounted) return;

    if (reply == null) {
      _consecutiveFails++;
      if (_consecutiveFails >= 2) {
        setState(() {});
        // Two consecutive failures — offer end option
      } else {
        // Single failure — show retry hint, stay in thinking state
        if (mounted) setState(() {});
      }
      return;
    }

    _consecutiveFails = 0;
    _retryText = null;
    _transcript.add({'role': 'model', 'text': reply});
    await _voice?.speak(reply);
  }

  Future<void> _handleUserSilent() async {
    // Send a silent-prompt turn to keep conversation alive
    await _handleUserTurn('[user has been quiet - ask them an easy question]');
  }

  List<Map<String, String>> _buildHistory() {
    // Trim to last 8 pairs
    final pairs = <Map<String, String>>[];
    for (final t in _transcript) {
      pairs.add({'role': t['role']!, 'text': t['text']!});
    }
    if (pairs.length > 16) {
      return pairs.sublist(pairs.length - 16);
    }
    return pairs;
  }

  Future<void> _retryLastTurn() async {
    final text = _retryText;
    if (text == null) return;
    _consecutiveFails = 0;
    // Remove the failed user turn from transcript before retrying
    if (_transcript.isNotEmpty && _transcript.last['role'] == 'user') {
      _transcript.removeLast();
    }
    await _handleUserTurn(text);
  }

  void _toggleMic() {
    setState(() => _micMuted = !_micMuted);
    if (_micMuted) {
      _voice?.pauseListening();
    } else {
      _voice?.resumeListening();
    }
  }

  Future<void> _confirmEnd() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCallBgBottom,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('End Practice?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('End your session with Shivani?',
            style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay', style: TextStyle(color: kCyan, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('End', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) _endCall();
  }

  Future<void> _endCall({bool autoEnd = false}) async {
    _timer?.cancel();
    await _voice?.stopAll();

    AnalyticsService.instance.logAiSessionEnded(_elapsed, _transcript.length);
    ReviewService.instance.recordSuccessfulCall(_elapsed);
    ReviewService.pendingCheck = true;

    if (!mounted) return;

    if (autoEnd) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Time\'s Up!',
              style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
          content: const Text('Great practice session! See your feedback below.',
              style: TextStyle(color: kTextSecondary)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('See Feedback'),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;

    // Request feedback from backend (fire-and-forget timing — we await here
    // to show the sheet, but navigation happens regardless of result)
    final feedback = _sessionId != null
        ? await _service.endSession(_sessionId!, _transcript, _elapsed)
        : null;

    if (!mounted) return;

    if (feedback != null) {
      final score = (feedback['score'] as num?)?.toInt() ?? 0;
      AnalyticsService.instance.logAiFeedbackShown(score);
      await _showFeedbackSheet(feedback);
    }

    if (mounted) context.go('/home');
  }

  Future<void> _showFeedbackSheet(Map<String, dynamic> feedback) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FeedbackSheet(feedback: feedback),
    );
  }

  void _showDailyLimitDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Daily Limit Reached",
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          "You've used today's $kAiDailyLimit free AI sessions with Shivani. "
          "Come back tomorrow, or find a human partner!",
          style: const TextStyle(color: kTextSecondary),
        ),
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
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String get _elapsedLabel {
    final m = _elapsed ~/ 60;
    final s = _elapsed % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _stateLabel(AiVoiceState s) {
    switch (s) {
      case AiVoiceState.listening:
        return 'Listening…';
      case AiVoiceState.thinking:
        return 'Shivani is thinking…';
      case AiVoiceState.speaking:
        return 'Shivani is speaking…';
      case AiVoiceState.error:
        return 'Mic error — check permissions';
      case AiVoiceState.idle:
        return _micMuted ? 'Mic muted' : '';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _voice?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_starting) {
      return const Scaffold(
        backgroundColor: kCallBgTop,
        body: Center(child: CircularProgressIndicator(color: kCyan)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _confirmEnd(),
      child: Scaffold(
        backgroundColor: kCallBgTop,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kCallBgTop, kCallBgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Timer row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _elapsedLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Avatar + name + badge
                ValueListenableBuilder<AiVoiceState>(
                  valueListenable: _voice?.state ?? ValueNotifier(AiVoiceState.idle),
                  builder: (_, voiceState, __) {
                    final isSpeaking = voiceState == AiVoiceState.speaking;
                    return Column(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, child) => Transform.scale(
                            scale: isSpeaking ? _pulseAnim.value : 1.0,
                            child: child,
                          ),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSpeaking
                                    ? kCyan.withOpacity(0.85)
                                    : Colors.white24,
                                width: isSpeaking ? 3.0 : 1.5,
                              ),
                              boxShadow: isSpeaking
                                  ? [
                                      BoxShadow(
                                        color: kCyan.withOpacity(0.4),
                                        blurRadius: 28,
                                        spreadRadius: 4,
                                      )
                                    ]
                                  : [],
                            ),
                            child: ClipOval(
                              child: UserAvatar(
                                imageUrl: kAiPartnerAvatar,
                                name: kAiPartnerName,
                                radius: 60,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          kAiPartnerName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: kCyan.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kCyan.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'AI Partner',
                            style: TextStyle(
                              color: kCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // State label
                        Text(
                          _stateLabel(voiceState),
                          style: TextStyle(
                            color: voiceState == AiVoiceState.speaking ? kCyan : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Partial transcript area
                ValueListenableBuilder<String>(
                  valueListenable: _voice?.partialText ?? ValueNotifier(''),
                  builder: (_, partial, __) {
                    if (partial.isEmpty) return const SizedBox(height: 48);
                    return Container(
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        partial,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    );
                  },
                ),

                // Error / retry area
                if (_consecutiveFails >= 2) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Text(
                          'Connection hiccup — tap to retry',
                          style: TextStyle(color: Colors.amber, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: _retryLastTurn,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.amber),
                                foregroundColor: Colors.amber,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              ),
                              child: const Text('Retry'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _endCall,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: kDanger),
                                foregroundColor: kDanger,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              ),
                              child: const Text('End'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(flex: 2),

                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mic mute
                      _ControlButton(
                        icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _micMuted ? 'Unmute' : 'Mute',
                        color: _micMuted ? Colors.amber : Colors.white,
                        onTap: _toggleMic,
                      ),
                      // End call
                      GestureDetector(
                        onTap: _confirmEnd,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            color: kDanger,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: kDanger, blurRadius: 16, spreadRadius: 1),
                            ],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                        ),
                      ),
                      // Placeholder to balance layout
                      const SizedBox(width: 56),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Control button widget ────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Feedback bottom sheet ────────────────────────────────────────────────────

class _FeedbackSheet extends StatelessWidget {
  final Map<String, dynamic> feedback;

  const _FeedbackSheet({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final score = feedback['score'] as int? ?? 0;
    final corrections = (feedback['corrections'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final strengths = (feedback['strengths'] as List<dynamic>? ?? []).cast<String>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Session Feedback',
            style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Practice session with $kAiPartnerName (AI Partner)',
            style: const TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          // Score badge
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kPrimary.withOpacity(0.15)),
            ),
            child: Column(
              children: [
                Text(
                  '$score/10',
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text('Overall Score',
                    style: TextStyle(color: kTextSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (strengths.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('What you did well',
                style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final s in strengths)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✓ ', style: TextStyle(color: kSuccess, fontSize: 14)),
                    Expanded(
                      child: Text(s, style: const TextStyle(color: kTextSecondary, fontSize: 14)),
                    ),
                  ],
                ),
              ),
          ],
          if (corrections.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Areas to improve',
                style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final c in corrections) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '❌  "${c['you_said']}"',
                      style: const TextStyle(
                          color: kDanger, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '✅  "${c['better']}"',
                      style: const TextStyle(
                          color: kSuccess, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if ((c['why'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        c['why'] as String,
                        style: const TextStyle(color: kTextMuted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Done',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
