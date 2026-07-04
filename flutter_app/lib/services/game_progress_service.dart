import 'package:shared_preferences/shared_preferences.dart';

class GameProgressService {
  GameProgressService._();
  static final GameProgressService instance = GameProgressService._();

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── Key helpers ───────────────────────────────────────────────────────────

  String _starsKey(String game, int level) => '${game}_stars_$level';
  String _bestKey(String game, int level) => '${game}_best_$level';

  static const _streakCountKey = 'streak_count';
  static const _streakDateKey = 'streak_last_date';
  static const _totalGamesKey = 'total_games';
  static const _totalCorrectKey = 'total_correct';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<int> getStars(String game, int level) async =>
      (await _p).getInt(_starsKey(game, level)) ?? 0;

  Future<int> getBestScore(String game, int level) async =>
      (await _p).getInt(_bestKey(game, level)) ?? 0;

  Future<int> getStreak() async => (await _p).getInt(_streakCountKey) ?? 0;

  Future<Map<String, int>> getStats() async {
    final p = await _p;
    return {
      'total_games': p.getInt(_totalGamesKey) ?? 0,
      'total_correct': p.getInt(_totalCorrectKey) ?? 0,
      'streak': p.getInt(_streakCountKey) ?? 0,
    };
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> saveResult(
      String game, int level, int score, int total) async {
    final p = await _p;
    final stars = _calcStars(score, total);

    // Best stars (never decrease)
    final prevStars = p.getInt(_starsKey(game, level)) ?? 0;
    if (stars > prevStars) await p.setInt(_starsKey(game, level), stars);

    // Best score (never decrease)
    final prevBest = p.getInt(_bestKey(game, level)) ?? 0;
    if (score > prevBest) await p.setInt(_bestKey(game, level), score);

    // Lifetime stats
    await p.setInt(_totalGamesKey, (p.getInt(_totalGamesKey) ?? 0) + 1);
    await p.setInt(
        _totalCorrectKey, (p.getInt(_totalCorrectKey) ?? 0) + score);

    await _updateStreak(p);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  int _calcStars(int score, int total) {
    if (total == 0) return 0;
    final pct = score / total;
    if (pct >= 0.9) return 3;
    if (pct >= 0.6) return 2;
    if (pct > 0) return 1;
    return 0;
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _updateStreak(SharedPreferences p) async {
    final today = _todayStr();
    final last = p.getString(_streakDateKey) ?? '';
    if (last == today) return; // already played today

    int streak = p.getInt(_streakCountKey) ?? 0;
    if (last.isNotEmpty) {
      try {
        final lastDate = DateTime.parse(last);
        final todayDate = DateTime.now();
        final diff = DateTime(todayDate.year, todayDate.month, todayDate.day)
            .difference(
                DateTime(lastDate.year, lastDate.month, lastDate.day))
            .inDays;
        streak = diff == 1 ? streak + 1 : 1;
      } catch (_) {
        streak = 1;
      }
    } else {
      streak = 1;
    }

    await p.setInt(_streakCountKey, streak);
    await p.setString(_streakDateKey, today);
  }
}
