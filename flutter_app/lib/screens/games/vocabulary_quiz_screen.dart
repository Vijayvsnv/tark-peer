import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/game_progress_service.dart';

// ── Data ─────────────────────────────────────────────────────────────────────

class _Q {
  final String word;
  final String correct;
  final List<String> wrong;
  const _Q({required this.word, required this.correct, required this.wrong});
}

const _level1 = [
  _Q(word: 'Curious', correct: 'Eager to know or learn', wrong: ['Feeling very tired', 'Moving very fast', 'Being very angry']),
  _Q(word: 'Ancient', correct: 'Belonging to the very distant past', wrong: ['Brand new', 'Very colorful', 'Quite small']),
  _Q(word: 'Brilliant', correct: 'Exceptionally clever or talented', wrong: ['Very dark', 'Extremely lazy', 'Quite slow']),
  _Q(word: 'Fragile', correct: 'Easily broken or damaged', wrong: ['Very strong', 'Extremely heavy', 'Completely safe']),
  _Q(word: 'Generous', correct: 'Willing to give freely to others', wrong: ['Very greedy', 'Always angry', 'Extremely shy']),
  _Q(word: 'Exhausted', correct: 'Completely drained of energy', wrong: ['Feeling excited', 'Very hungry', 'Perfectly healthy']),
  _Q(word: 'Enormous', correct: 'Very large in size or amount', wrong: ['Very tiny', 'Extremely quiet', 'Quite cheap']),
  _Q(word: 'Humble', correct: 'Modest, not proud or arrogant', wrong: ['Very proud', 'Always loud', 'Extremely rich']),
  _Q(word: 'Vivid', correct: 'Producing powerful, clear images', wrong: ['Dull and boring', 'Very quiet', 'Extremely cold']),
  _Q(word: 'Frequent', correct: 'Happening many times at short intervals', wrong: ['Rarely happening', 'Very noisy', 'Quite expensive']),
];

const _level2 = [
  _Q(word: 'Ambiguous', correct: 'Open to more than one interpretation', wrong: ['Completely clear', 'Very boring', 'Quite heavy']),
  _Q(word: 'Eloquent', correct: 'Fluent and persuasive in speaking', wrong: ['Unable to speak', 'Very silent', 'Quite rude']),
  _Q(word: 'Benevolent', correct: 'Well-meaning and kind toward others', wrong: ['Cruel and unkind', 'Very selfish', 'Quite lazy']),
  _Q(word: 'Contemplate', correct: 'Think deeply and at length about something', wrong: ['Act without thinking', 'Speak very loudly', 'Run very fast']),
  _Q(word: 'Diligent', correct: 'Showing careful and steady effort', wrong: ['Very careless', 'Extremely slow', 'Quite loud']),
  _Q(word: 'Fervent', correct: 'Having passionate and intense feeling', wrong: ['Completely calm', 'Very cold', 'Quite dull']),
  _Q(word: 'Gratitude', correct: 'The quality of being thankful', wrong: ['Feeling of anger', 'Sense of pride', 'Feeling of jealousy']),
  _Q(word: 'Inevitable', correct: 'Certain to happen, impossible to avoid', wrong: ['Easily prevented', 'Very unlikely', 'Not important']),
  _Q(word: 'Jubilant', correct: 'Feeling or expressing great happiness', wrong: ['Deeply sad', 'Very tired', 'Quite confused']),
  _Q(word: 'Resilient', correct: 'Able to recover quickly from difficulties', wrong: ['Easily defeated', 'Very weak', 'Quite fragile']),
];

const _level3 = [
  _Q(word: 'Ephemeral', correct: 'Lasting for a very short time only', wrong: ['Lasting forever', 'Very important', 'Quite large']),
  _Q(word: 'Ubiquitous', correct: 'Present or found everywhere', wrong: ['Extremely rare', 'Very small', 'Quite ancient']),
  _Q(word: 'Pragmatic', correct: 'Dealing with things sensibly and realistically', wrong: ['Idealistic and impractical', 'Very emotional', 'Quite abstract']),
  _Q(word: 'Melancholy', correct: 'A deep feeling of pensive sadness', wrong: ['Extreme happiness', 'Strong anger', 'Deep hunger']),
  _Q(word: 'Verbose', correct: 'Using far more words than needed', wrong: ['Speaking very briefly', 'Completely silent', 'Very polite']),
  _Q(word: 'Tenacious', correct: 'Holding firmly to a purpose or belief', wrong: ['Giving up easily', 'Very flexible', 'Quite forgetful']),
  _Q(word: 'Ambivalent', correct: 'Having mixed or contradictory feelings', wrong: ['Very certain', 'Completely happy', 'Quite angry']),
  _Q(word: 'Pensive', correct: 'Engaged in deep thoughtful reflection', wrong: ['Acting without thought', 'Very playful', 'Quite noisy']),
  _Q(word: 'Meticulous', correct: 'Showing great attention to detail', wrong: ['Very careless', 'Quite lazy', 'Completely random']),
  _Q(word: 'Loquacious', correct: 'Tending to talk a great deal', wrong: ['Very quiet and reserved', 'Quite shy', 'Completely silent']),
];

List<_Q> _questionsForLevel(int level) {
  if (level == 2) return _level2;
  if (level == 3) return _level3;
  return _level1;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class VocabularyQuizScreen extends StatefulWidget {
  final int level;
  const VocabularyQuizScreen({super.key, this.level = 1});

  @override
  State<VocabularyQuizScreen> createState() => _VocabularyQuizScreenState();
}

class _VocabularyQuizScreenState extends State<VocabularyQuizScreen>
    with TickerProviderStateMixin {
  late List<_Q> _questions;
  late List<List<String>> _shuffledOptions;
  int _qIndex = 0;
  int _score = 0;
  String? _selected;
  bool _answered = false;
  bool _done = false;
  Timer? _nextTimer;

  late AnimationController _cardCtrl;
  late Animation<double> _cardAnim;

  @override
  void initState() {
    super.initState();
    final pool = List<_Q>.from(_questionsForLevel(widget.level))..shuffle(Random());
    _questions = pool.take(10).toList();
    _shuffledOptions = _questions.map((q) {
      return ([q.correct, ...q.wrong]..shuffle(Random()));
    }).toList();

    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _cardAnim = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _nextTimer?.cancel();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _select(String option) {
    if (_answered) return;
    setState(() {
      _selected = option;
      _answered = true;
      if (option == _questions[_qIndex].correct) _score++;
    });
    _nextTimer = Timer(const Duration(milliseconds: 900), _next);
  }

  void _next() {
    if (_qIndex + 1 >= _questions.length) {
      // Save progress
      GameProgressService.instance.saveResult('vocab', widget.level, _score, _questions.length);
      setState(() => _done = true);
      return;
    }
    _cardCtrl.reset();
    setState(() {
      _qIndex++;
      _selected = null;
      _answered = false;
    });
    _cardCtrl.forward();
  }

  void _restart() {
    _cardCtrl.reset();
    final pool = List<_Q>.from(_questionsForLevel(widget.level))..shuffle(Random());
    setState(() {
      _questions = pool.take(10).toList();
      _shuffledOptions = _questions.map((q) {
        return ([q.correct, ...q.wrong]..shuffle(Random()));
      }).toList();
      _qIndex = 0;
      _score = 0;
      _selected = null;
      _answered = false;
      _done = false;
    });
    _cardCtrl.forward();
  }

  int get _stars {
    final pct = _score / _questions.length;
    if (pct >= 0.9) return 3;
    if (pct >= 0.6) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Level ${widget.level} — Vocabulary',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$_score/${_questions.length}',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
      body: _done ? _buildResult() : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    final q = _questions[_qIndex];
    final opts = _shuffledOptions[_qIndex];
    final progress = (_qIndex + 1) / _questions.length;

    return Column(
      children: [
        LinearProgressIndicator(value: progress, backgroundColor: kSurface, color: kPrimary, minHeight: 4),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${_qIndex + 1} of ${_questions.length}',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              Text('Score: $_score', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FadeTransition(
          opacity: _cardAnim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero).animate(_cardAnim),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(
                  children: [
                    const Text('What does this word mean?', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Text(q.word, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: opts.map((opt) => _OptionButton(
              text: opt,
              isCorrect: opt == q.correct,
              isSelected: opt == _selected,
              answered: _answered,
              onTap: () => _select(opt),
            )).toList(),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i < _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: i < _stars ? Colors.amber : kTextMuted,
                  size: 44,
                ),
              )),
            ),
            const SizedBox(height: 20),
            const Text('Level Complete!', style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('$_score out of ${_questions.length} correct', style: const TextStyle(color: kTextSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _score >= 9 ? 'Outstanding!' : _score >= 6 ? 'Good job!' : 'Keep practicing!',
              style: TextStyle(color: _score >= 6 ? kPrimary : kTextSecondary, fontSize: 15, fontWeight: FontWeight.w600),
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

class _OptionButton extends StatelessWidget {
  final String text;
  final bool isCorrect;
  final bool isSelected;
  final bool answered;
  final VoidCallback onTap;

  const _OptionButton({
    required this.text, required this.isCorrect,
    required this.isSelected, required this.answered, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = kSurface;
    Color border = kBorder;
    Color textColor = kTextPrimary;
    Widget? trailing;

    if (answered) {
      if (isCorrect) {
        bg = const Color(0xFFDCFCE7); border = Colors.green; textColor = const Color(0xFF166534);
        trailing = const Icon(Icons.check_circle, color: Colors.green, size: 20);
      } else if (isSelected) {
        bg = const Color(0xFFFEE2E2); border = Colors.red; textColor = const Color(0xFF991B1B);
        trailing = const Icon(Icons.cancel, color: Colors.red, size: 20);
      }
    }

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: answered && (isCorrect || isSelected) ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
