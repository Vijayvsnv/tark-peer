import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/ai_partner_service.dart';

class AiTab extends StatefulWidget {
  const AiTab({super.key});

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  final _service = AiPartnerService();
  int _used = 0;
  int _remaining = kAiDailyLimit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final q = await _service.getQuota();
      if (mounted) {
        setState(() {
          _used = q.used;
          _remaining = q.remaining;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startSession() {
    if (_remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily limit reached ($_used/$kAiDailyLimit sessions used). Come back tomorrow!',
          ),
          backgroundColor: kDanger,
        ),
      );
      return;
    }
    context.push('/ai-call', extra: 'home_button');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadQuota,
      color: kCyan,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // ── Shivani profile card ──────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kCallBgTop, kCallBgBottom],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: kCyan.withOpacity(0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar with glow ring
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kCyan, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: kCyan.withOpacity(0.35),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: SvgPicture.asset(
                          'assets/images/shivani_avatar.svg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name
                    const Text(
                      kAiPartnerName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // AI badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: kCyan.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kCyan.withOpacity(0.6)),
                      ),
                      child: const Text(
                        'AI English Practice Partner',
                        style: TextStyle(
                          color: kCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Bio
                    const Text(
                      'Practice spoken English anytime — no waiting, no judgment. '
                      'Shivani listens, corrects, and encourages you to speak better.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Quota bar
                    if (!_loading) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sessions today',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          Text(
                            '$_used / $kAiDailyLimit',
                            style: TextStyle(
                              color: _remaining > 0 ? kCyan : kDanger,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _used / kAiDailyLimit,
                          backgroundColor: Colors.white12,
                          color: _remaining > 0 ? kCyan : kDanger,
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Start button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _remaining > 0 ? _startSession : null,
                        icon: const Icon(Icons.mic_rounded, size: 20),
                        label: Text(
                          _remaining > 0
                              ? 'Start Practice with Shivani'
                              : 'No sessions left today',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _remaining > 0 ? kCyan : Colors.white24,
                          foregroundColor: _remaining > 0 ? Colors.white : Colors.white54,
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── What Shivani can do ───────────────────────────────────
              Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'What you can practice',
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _FeatureCard(
                icon: Icons.record_voice_over_rounded,
                color: const Color(0xFF11998E),
                title: 'Spoken English',
                subtitle: 'Have real conversations and improve fluency',
              ),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.auto_fix_high_rounded,
                color: kPrimary,
                title: 'Grammar Corrections',
                subtitle: 'Shivani gently corrects mistakes as you speak',
              ),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.forum_rounded,
                color: const Color(0xFFF05423),
                title: 'Any Topic',
                subtitle: 'Daily life, work, travel, opinions — anything goes',
              ),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.insights_rounded,
                color: const Color(0xFF8B5CF6),
                title: 'Session Feedback',
                subtitle: 'Get a score + corrections report after each session',
              ),

              const SizedBox(height: 24),

              // ── How it works ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StepRow(number: '1', text: 'Shivani greets you and starts the conversation'),
                    _StepRow(number: '2', text: 'You speak — Shivani listens and replies'),
                    _StepRow(number: '3', text: 'End the session to get your feedback report'),
                    const SizedBox(height: 4),
                    Text(
                      'Sessions last up to 10 minutes · $kAiDailyLimit free sessions per day',
                      style: const TextStyle(color: kTextMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(color: kCyan, shape: BoxShape.circle),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: kTextSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
