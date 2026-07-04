import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/profile_service.dart';
import '../../services/game_progress_service.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  final _profileService = ProfileService();
  Map<String, dynamic>? _stats;
  Map<String, int>? _gameStats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    await Future.wait([
      Future(() async {
        try {
          final s = await _profileService.getCallStats();
          if (mounted) setState(() => _stats = s);
        } catch (_) {}
      }),
      Future(() async {
        try {
          final s = await GameProgressService.instance.getStats();
          if (mounted) setState(() => _gameStats = s);
        } catch (_) {}
      }),
    ]);
    if (mounted) setState(() => _loading = false);
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
    final s = _stats ?? {'total_calls': 0, 'total_seconds': 0, 'longest_seconds': 0, 'streak': 0, 'this_week': 0, 'last_week': 0};
    final totalCalls = s['total_calls'] as int;
    final totalSeconds = s['total_seconds'] as int;
    final longestSeconds = s['longest_seconds'] as int;
    final streak = s['streak'] as int;
    final thisWeek = s['this_week'] as int;
    final lastWeek = s['last_week'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totalCalls == 0) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Column(
                children: [
                  Icon(Icons.call_outlined, color: kTextMuted, size: 48),
                  const SizedBox(height: 12),
                  const Text('No calls yet',
                      style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Start calling to track your call progress!',
                      style: TextStyle(color: kTextSecondary, fontSize: 13)),
                ],
              ),
            ),
          ),
        ] else ...[
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
      ],  // end else block

        // ── Game Progress ──────────────────────────────────────────────────────
        if (_gameStats != null) ...[
          const SizedBox(height: 28),
          const Text(
            'GAME PROGRESS',
            style: TextStyle(color: kPrimary, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          const Text('Your English game stats', style: TextStyle(color: kTextSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          _gameStatsCard(),
        ],
      ],  // end children
    );
  }

  Widget _gameStatsCard() {
    final totalGames = _gameStats!['total_games'] ?? 0;
    final totalCorrect = _gameStats!['total_correct'] ?? 0;
    final gameStreak = _gameStats!['streak'] ?? 0;
    final accuracy = totalGames == 0 ? 0 : (totalCorrect / (totalGames * 10) * 100).round().clamp(0, 100);

    if (totalGames == 0) {
      return _card(
        child: Row(
          children: [
            Icon(Icons.games_rounded, color: kTextMuted, size: 32),
            const SizedBox(width: 14),
            const Expanded(
              child: Text('No games played yet — head to the Games tab to start!',
                  style: TextStyle(color: kTextSecondary, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  icon: Icons.games_rounded,
                  iconColor: const Color(0xFFFC5C7D),
                  value: '$totalGames',
                  label: 'Games Played',
                ),
              ),
              Container(width: 1, height: 56, color: kBorder),
              Expanded(
                child: _statBlock(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: kSuccess,
                  value: '$accuracy%',
                  label: 'Accuracy',
                ),
              ),
              Container(width: 1, height: 56, color: kBorder),
              Expanded(
                child: _statBlock(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFFF6B35),
                  value: gameStreak > 0 ? '$gameStreak 🔥' : '—',
                  label: 'Day Streak',
                ),
              ),
            ],
          ),
        ],
      ),
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
