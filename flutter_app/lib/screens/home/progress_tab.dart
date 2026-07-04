import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/profile_service.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  final _profileService = ProfileService();
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _profileService.getCallStats();
      if (mounted) setState(() { _stats = s; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTotal(int seconds) {
    if (seconds == 0) return '0 min';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatLongest(int seconds) {
    if (seconds == 0) return '—';
    final m = seconds ~/ 60;
    if (m == 0) return '<1 min';
    return '$m min';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YOUR PROGRESS',
              style: TextStyle(
                color: kPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'See how far you\'ve come',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: CircularProgressIndicator(color: kPrimary),
                    ),
                  )
                : _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final s = _stats!;
    final totalCalls = s['total_calls'] as int;
    final totalSeconds = s['total_seconds'] as int;
    final longestSeconds = s['longest_seconds'] as int;
    final streak = s['streak'] as int;
    final thisWeek = s['this_week'] as int;
    final lastWeek = s['last_week'] as int;

    if (totalCalls == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined, color: kTextMuted, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No calls yet',
                style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start calling to see your progress!',
                style: TextStyle(color: kTextSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Call Stats ────────────────────────────────────────────────────────
        _card(
          child: Row(
            children: [
              Expanded(
                child: _statBlock(
                  icon: Icons.call,
                  iconColor: kPrimary,
                  value: '$totalCalls',
                  label: 'Total Calls',
                ),
              ),
              Container(width: 1, height: 56, color: kBorder),
              Expanded(
                child: _statBlock(
                  icon: Icons.timer_outlined,
                  iconColor: kCyan,
                  value: _formatTotal(totalSeconds),
                  label: 'Total Time',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Streak ────────────────────────────────────────────────────────────
        _card(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kAccentSoft, kAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('🔥', style: TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      streak == 0 ? 'No streak yet' : '$streak day${streak == 1 ? '' : 's'} streak',
                      style: TextStyle(
                        color: streak > 0 ? kAccent : kTextSecondary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      streak == 0
                          ? 'Call today to start a streak!'
                          : 'Keep it going — call today!',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Longest Call ─────────────────────────────────────────────────────
        _card(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kSuccess.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(Icons.emoji_events_outlined, color: kSuccess, size: 26),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatLongest(longestSeconds),
                      style: const TextStyle(color: kSuccess, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Longest call',
                      style: TextStyle(color: kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── This Week vs Last Week ────────────────────────────────────────────
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Comparison',
                style: TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _weekBlock('This Week', thisWeek, kPrimary)),
                  const SizedBox(width: 12),
                  Expanded(child: _weekBlock('Last Week', lastWeek, kTextSecondary)),
                ],
              ),
              if (thisWeek > 0 || lastWeek > 0) ...[
                const SizedBox(height: 14),
                _weekBar(thisWeek, lastWeek),
                const SizedBox(height: 8),
                Text(
                  thisWeek > lastWeek
                      ? '↑ ${thisWeek - lastWeek} more than last week'
                      : thisWeek < lastWeek
                          ? '↓ ${lastWeek - thisWeek} fewer than last week'
                          : 'Same as last week',
                  style: TextStyle(
                    color: thisWeek >= lastWeek ? kSuccess : kDanger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kPrimaryDeep.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _statBlock({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _weekBlock(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _weekBar(int thisWeek, int lastWeek) {
    final max = thisWeek > lastWeek ? thisWeek : lastWeek;
    if (max == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          flex: thisWeek == 0 ? 1 : thisWeek,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            height: 8,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: lastWeek == 0 ? 1 : lastWeek,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: kBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}
