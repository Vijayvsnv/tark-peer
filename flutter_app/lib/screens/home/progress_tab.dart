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
              'Your Progress',
              style: TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
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
              Icon(Icons.bar_chart_outlined, color: kPrimary.withOpacity(0.3), size: 64),
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
              Container(width: 1, height: 56, color: Colors.white12),
              Expanded(
                child: _statBlock(
                  icon: Icons.timer_outlined,
                  iconColor: const Color(0xFF60A5FA),
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('🔥', style: TextStyle(fontSize: 24)),
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
                        color: streak > 0 ? Colors.orange : kTextSecondary,
                        fontSize: 18,
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.emoji_events_outlined, color: Colors.greenAccent, size: 26),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatLongest(longestSeconds),
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold),
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
                    color: thisWeek >= lastWeek ? Colors.greenAccent : const Color(0xFFFF6B6B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withOpacity(0.15)),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                height: 8,
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(4),
                ),
                width: double.infinity,
                constraints: BoxConstraints(
                  maxWidth: double.infinity,
                ),
              ),
            ],
          ),
          flex: thisWeek == 0 ? 1 : thisWeek,
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: lastWeek == 0 ? 1 : lastWeek,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: kTextSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}
