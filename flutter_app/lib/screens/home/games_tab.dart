import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/game_progress_service.dart';

class GamesTab extends StatefulWidget {
  const GamesTab({super.key});

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  int _streak = 0;
  // stars & best per game per level: key = 'gameId_level'
  final Map<String, int> _stars = {};
  final Map<String, int> _best = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final svc = GameProgressService.instance;
    const games = ['vocab', 'scramble', 'fill', 'pronun', 'dict'];
    final futures = <Future<int>>[];
    futures.add(svc.getStreak());
    for (final g in games) {
      for (int l = 1; l <= 3; l++) {
        futures.add(svc.getStars(g, l));
        futures.add(svc.getBestScore(g, l));
      }
    }
    final results = await Future.wait(futures);
    if (!mounted) return;
    int i = 1;
    final stars = <String, int>{};
    final best = <String, int>{};
    for (final g in games) {
      for (int l = 1; l <= 3; l++) {
        stars['${g}_$l'] = results[i++];
        best['${g}_$l'] = results[i++];
      }
    }
    setState(() {
      _streak = results[0];
      _stars.addAll(stars);
      _best.addAll(best);
    });
  }

  int _starsFor(String g, int l) => _stars['${g}_$l'] ?? 0;
  int _bestFor(String g, int l) => _best['${g}_$l'] ?? 0;
  bool _locked(String g, int l) => l > 1 && _starsFor(g, l - 1) < 1;

  Future<void> _open(String route) async {
    await context.push(route);
    _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('English Games',
              style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Play games and improve your English',
              style: TextStyle(color: kTextSecondary, fontSize: 14)),
          const SizedBox(height: 20),

          // ── Streak banner ───────────────────────────────────────────────
          if (_streak > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFFFF6B35).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_streak Day${_streak == 1 ? '' : 's'} Streak!',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Text('Keep playing every day to maintain it',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Vocabulary Quiz ─────────────────────────────────────────────
          _MultiLevelCard(
            title: 'Vocabulary Quiz',
            description: 'Choose the correct meaning of English words',
            icon: Icons.quiz_rounded,
            colors: const [Color(0xFF6C63FF), Color(0xFF3B82F6)],
            levels: [
              _LevelData(1, 'Basic', _locked('vocab', 1), _starsFor('vocab', 1), _bestFor('vocab', 1)),
              _LevelData(2, 'Medium', _locked('vocab', 2), _starsFor('vocab', 2), _bestFor('vocab', 2)),
              _LevelData(3, 'Hard', _locked('vocab', 3), _starsFor('vocab', 3), _bestFor('vocab', 3)),
            ],
            onPlay: (l) => _open('/games/vocab?level=$l'),
          ),
          const SizedBox(height: 14),

          // ── Word Scramble ───────────────────────────────────────────────
          _MultiLevelCard(
            title: 'Word Scramble',
            description: 'Unscramble the letters to form the correct word',
            icon: Icons.shuffle_rounded,
            colors: const [Color(0xFFFC5C7D), Color(0xFFFF8C61)],
            levels: [
              _LevelData(1, 'Easy', _locked('scramble', 1), _starsFor('scramble', 1), _bestFor('scramble', 1)),
              _LevelData(2, 'Medium', _locked('scramble', 2), _starsFor('scramble', 2), _bestFor('scramble', 2)),
              _LevelData(3, 'Hard', _locked('scramble', 3), _starsFor('scramble', 3), _bestFor('scramble', 3)),
            ],
            onPlay: (l) => _open('/games/scramble?level=$l'),
          ),
          const SizedBox(height: 14),

          // ── Fill in the Blanks ──────────────────────────────────────────
          _MultiLevelCard(
            title: 'Fill in the Blanks',
            description: 'Complete sentences with the missing word',
            icon: Icons.edit_note_rounded,
            colors: const [Color(0xFF43E97B), Color(0xFF38F9D7)],
            levels: [
              _LevelData(1, 'Easy', _locked('fill', 1), _starsFor('fill', 1), _bestFor('fill', 1)),
              _LevelData(2, 'Medium', _locked('fill', 2), _starsFor('fill', 2), _bestFor('fill', 2)),
              _LevelData(3, 'Hard', _locked('fill', 3), _starsFor('fill', 3), _bestFor('fill', 3)),
            ],
            onPlay: (l) => _open('/games/fill?level=$l'),
          ),
          const SizedBox(height: 14),

          // ── Pronunciation Challenge ─────────────────────────────────────
          _MultiLevelCard(
            title: 'Pronunciation Challenge',
            description: 'Say the word aloud — mic checks your pronunciation',
            icon: Icons.record_voice_over_rounded,
            colors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
            levels: [
              _LevelData(1, 'Easy', _locked('pronun', 1), _starsFor('pronun', 1), _bestFor('pronun', 1)),
              _LevelData(2, 'Medium', _locked('pronun', 2), _starsFor('pronun', 2), _bestFor('pronun', 2)),
              _LevelData(3, 'Hard', _locked('pronun', 3), _starsFor('pronun', 3), _bestFor('pronun', 3)),
            ],
            onPlay: (l) => _open('/games/pronun?level=$l'),
          ),
          const SizedBox(height: 14),

          // ── Dictation ───────────────────────────────────────────────────
          _MultiLevelCard(
            title: 'Dictation',
            description: 'Listen to the sentence and type what you hear',
            icon: Icons.headphones_rounded,
            colors: const [Color(0xFFF7971E), Color(0xFFFFD200)],
            levels: [
              _LevelData(1, 'Easy', _locked('dict', 1), _starsFor('dict', 1), _bestFor('dict', 1)),
              _LevelData(2, 'Medium', _locked('dict', 2), _starsFor('dict', 2), _bestFor('dict', 2)),
              _LevelData(3, 'Hard', _locked('dict', 3), _starsFor('dict', 3), _bestFor('dict', 3)),
            ],
            onPlay: (l) => _open('/games/dict?level=$l'),
          ),
        ],
      ),
    );
  }
}

// ── Level data ────────────────────────────────────────────────────────────────

class _LevelData {
  final int level;
  final String label;
  final bool locked;
  final int stars;
  final int best;
  const _LevelData(this.level, this.label, this.locked, this.stars, this.best);
}

// ── Multi-level game card ─────────────────────────────────────────────────────

class _MultiLevelCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> colors;
  final List<_LevelData> levels;
  final void Function(int level) onPlay;

  const _MultiLevelCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.colors,
    required this.levels,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final anyPlayed = levels.any((l) => l.stars > 0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: colors[0].withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(description,
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                      ],
                    ),
                  ),
                  if (anyPlayed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('IN PROGRESS',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('AVAILABLE',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: levels.map((l) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: l.locked
                            ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Complete Level ${l.level - 1} with ≥1 star to unlock!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ))
                            : () => onPlay(l.level),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                          decoration: BoxDecoration(
                            color: l.locked ? Colors.white.withOpacity(0.12) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (l.locked)
                                const Icon(Icons.lock_rounded, color: Colors.white54, size: 16)
                              else if (l.stars > 0)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(3, (i) => Icon(
                                    i < l.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: i < l.stars ? Colors.amber : colors[0].withOpacity(0.3),
                                    size: 12,
                                  )),
                                )
                              else
                                Icon(Icons.play_arrow_rounded, color: colors[0], size: 18),
                              const SizedBox(height: 3),
                              Text('Lv ${l.level}',
                                  style: TextStyle(
                                    color: l.locked ? Colors.white38 : colors[0],
                                    fontSize: 11, fontWeight: FontWeight.bold,
                                  )),
                              Text(l.label,
                                  style: TextStyle(
                                    color: l.locked ? Colors.white30 : colors[0].withOpacity(0.7),
                                    fontSize: 10,
                                  )),
                              if (!l.locked && l.best > 0) ...[
                                const SizedBox(height: 2),
                                Text('Best ${l.best}/10',
                                    style: TextStyle(color: colors[0].withOpacity(0.55), fontSize: 9)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
