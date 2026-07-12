import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import '../../services/game_progress_service.dart';

// ── Word pools ────────────────────────────────────────────────────────────────

const _easy = [
  'CAT', 'DOG', 'SUN', 'MAP', 'FLY', 'CUP', 'BIG', 'RED', 'HOT', 'BOX',
  'STAR', 'BOOK', 'FISH', 'HAND', 'TREE', 'BIRD', 'RAIN', 'JUMP', 'PLAY', 'HOME',
  'CAKE', 'FIRE', 'GOLD', 'LION', 'MOON', 'PARK', 'ROAD', 'SHIP', 'WIND', 'DOOR',
];

const _medium = [
  'GARDEN', 'YELLOW', 'SIMPLE', 'CASTLE', 'BUTTER', 'CANDLE', 'ANCHOR',
  'KITCHEN', 'DOLPHIN', 'CAPTAIN', 'JOURNEY', 'PICTURE', 'MONSTER', 'CHICKEN',
  'PLASTIC', 'MORNING', 'HOLIDAY', 'CAREFUL', 'ANCIENT', 'FOREIGN',
  'BLANKET', 'COMFORT', 'DIAMOND', 'ENGLISH', 'FREEDOM', 'GENERAL',
  'HISTORY', 'IMAGINE', 'JUSTICE', 'KINGDOM',
];

const _hard = [
  'BEAUTIFUL', 'ADVENTURE', 'KNOWLEDGE', 'CELEBRATE', 'EMERGENCY',
  'WONDERFUL', 'CHALLENGE', 'EDUCATION', 'DANGEROUS', 'TELEPHONE',
  'IMPORTANT', 'FANTASTIC', 'HAPPINESS', 'EXCELLENT', 'AMBITIOUS',
  'BRILLIANT', 'CONFIDENT', 'ENCOURAGE', 'VOLUNTEER', 'COMMUNITY',
  'COUNTLESS', 'DEVELOPED', 'ELABORATE', 'FAVORABLE', 'GUARANTEE',
  'HEARTBEAT', 'INNOCENCE', 'LANDSCAPE', 'MOTIVATED', 'NECESSARY',
];

List<String> _poolForLevel(int level) {
  if (level == 2) return _medium;
  if (level == 3) return _hard;
  return _easy;
}

String _levelName(int level) {
  if (level == 2) return 'Medium';
  if (level == 3) return 'Hard';
  return 'Easy';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class WordScrambleScreen extends StatefulWidget {
  final int level;
  const WordScrambleScreen({super.key, this.level = 1});

  @override
  State<WordScrambleScreen> createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  late List<String> _pool;
  int _wIndex = 0;
  int _score = 0;
  final int _total = 10;
  bool _done = false;
  bool _answered = false;
  bool _correct = false;

  late String _word;
  late List<String> _origTiles;
  late List<bool> _tileUsed;
  late List<int?> _answerSources;

  @override
  void initState() {
    super.initState();
    _pool = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();
    _loadWordData();
  }

  void _loadWordData() {
    _word = _pool[_wIndex];
    final chars = _word.split('');
    int attempts = 0;
    do {
      chars.shuffle(Random());
      attempts++;
    } while (chars.join() == _word && _word.length > 1 && attempts < 100);
    _origTiles = List.from(chars);
    _tileUsed = List.filled(_word.length, false);
    _answerSources = List.filled(_word.length, null);
    _answered = false;
    _correct = false;
  }

  void _tapTile(int i) {
    if (_tileUsed[i] || _answered) return;
    final slot = _answerSources.indexOf(null);
    if (slot == -1) return;
    setState(() {
      _tileUsed[i] = true;
      _answerSources[slot] = i;
    });
    _checkComplete();
  }

  void _tapSlot(int slot) {
    if (_answerSources[slot] == null || _answered) return;
    final tileIdx = _answerSources[slot]!;
    setState(() {
      _tileUsed[tileIdx] = false;
      _answerSources[slot] = null;
    });
  }

  void _checkComplete() {
    if (_answerSources.any((s) => s == null)) return;
    final answer = _answerSources.map((i) => _origTiles[i!]).join();
    setState(() {
      _answered = true;
      _correct = answer == _word;
      if (_correct) _score++;
    });
  }

  Future<void> _next() async {
    if (_wIndex + 1 >= _total) {
      await GameProgressService.instance.saveResult('scramble', widget.level, _score, _total);
      AnalyticsService.instance.logGamePlayed('scramble', widget.level, _score);
      setState(() => _done = true);
      return;
    }
    setState(() {
      _wIndex++;
      _loadWordData();
    });
  }

  void _reshuffle() {
    final chars = _word.split('');
    int attempts = 0;
    do {
      chars.shuffle(Random());
      attempts++;
    } while (chars.join() == _word && _word.length > 1 && attempts < 100);
    setState(() {
      _origTiles = List.from(chars);
      _tileUsed = List.filled(_word.length, false);
      _answerSources = List.filled(_word.length, null);
    });
  }

  void _restart() {
    _pool = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();
    setState(() {
      _wIndex = 0;
      _score = 0;
      _done = false;
      _loadWordData();
    });
  }

  int get _stars {
    final pct = _score / _total;
    if (pct >= 0.9) return 3;
    if (pct >= 0.6) return 2;
    return 1;
  }

  static const _cardColors = [Color(0xFFFC5C7D), Color(0xFFFF8C61)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(
          'Level ${widget.level} — Word Scramble',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('$_score/$_total',
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: _done ? _buildResult() : _buildGame(),
    );
  }

  Widget _buildGame() {
    final progress = (_wIndex + 1) / _total;
    return Column(
      children: [
        LinearProgressIndicator(value: progress, backgroundColor: kSurface, color: kPrimary, minHeight: 4),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Word ${_wIndex + 1} of $_total',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              Text('Score: $_score', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Instruction card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: _cardColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: _cardColors[0].withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                Text('${_levelName(widget.level)} — Unscramble the word',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                Text(
                  _origTiles.join('  '),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Answer slots
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_word.length, (i) {
              final tileIdx = _answerSources[i];
              final char = tileIdx != null ? _origTiles[tileIdx] : null;
              final ok = _answered && char == _word[i];
              final bad = _answered && char != null && char != _word[i];
              return GestureDetector(
                onTap: () => _tapSlot(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 50,
                  decoration: BoxDecoration(
                    color: _answered
                        ? (ok ? const Color(0xFFDCFCE7) : bad ? const Color(0xFFFEE2E2) : kSurface)
                        : (char != null ? Colors.white : kSurface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _answered
                          ? (ok ? Colors.green : bad ? Colors.red : kBorder)
                          : (char != null ? _cardColors[0] : kBorder),
                      width: (char != null || _answered) ? 1.5 : 1,
                    ),
                    boxShadow: char != null && !_answered
                        ? [BoxShadow(color: _cardColors[0].withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      char ?? '',
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: _answered
                            ? (ok ? Colors.green : bad ? Colors.red : kTextSecondary)
                            : (char != null ? _cardColors[0] : kTextMuted),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        if (_answered) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _correct ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _correct ? Colors.green : Colors.red),
              ),
              child: Row(
                children: [
                  Icon(_correct ? Icons.check_circle : Icons.cancel,
                      color: _correct ? Colors.green : Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _correct ? 'Correct! Well done!' : 'The answer was: $_word',
                      style: TextStyle(
                        color: _correct ? const Color(0xFF166534) : const Color(0xFF991B1B),
                        fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const Spacer(),

        // Scrambled tiles
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8, runSpacing: 8,
            children: List.generate(_origTiles.length, (i) {
              final used = _tileUsed[i];
              return GestureDetector(
                onTap: (used || _answered) ? null : () => _tapTile(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48, height: 52,
                  decoration: BoxDecoration(
                    color: used ? kSurface : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: used ? kBorder : _cardColors[0],
                      width: used ? 1 : 1.5,
                    ),
                    boxShadow: used ? null : [
                      BoxShadow(color: _cardColors[0].withOpacity(0.18), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _origTiles[i],
                      style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: used ? kTextMuted : _cardColors[0],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _answered
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      _wIndex + 1 >= _total ? 'See Results' : 'Next Word →',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _reshuffle,
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: const Text('Reshuffle'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: kBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          foregroundColor: kTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _tileUsed = List.filled(_word.length, false);
                            _answerSources = List.filled(_word.length, null);
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: kBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          foregroundColor: kTextSecondary,
                        ),
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shuffle_rounded, size: 56, color: Color(0xFFFC5C7D)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i < _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: i < _stars ? Colors.amber : kTextMuted, size: 44,
                ),
              )),
            ),
            const SizedBox(height: 16),
            const Text('Word Scramble Complete!',
                style: TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('$_score out of $_total correct',
                style: const TextStyle(color: kTextSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _score >= 9 ? 'Outstanding!' : _score >= 6 ? 'Good job!' : 'Keep practicing!',
              style: TextStyle(
                color: _score >= 6 ? kPrimary : kTextSecondary,
                fontSize: 15, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Play Again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: kBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Back to Games', style: TextStyle(color: kTextSecondary, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
