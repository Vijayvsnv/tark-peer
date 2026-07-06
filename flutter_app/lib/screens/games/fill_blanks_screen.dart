import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/game_progress_service.dart';

// ── Data ─────────────────────────────────────────────────────────────────────

class _FQ {
  final String sentence;
  final String correct;
  final List<String> wrong;
  const _FQ({required this.sentence, required this.correct, required this.wrong});
}

const _level1 = [
  _FQ(sentence: 'She ___ to school every day.', correct: 'goes', wrong: ['gone', 'going', 'went']),
  _FQ(sentence: 'The sky is ___ during the day.', correct: 'blue', wrong: ['green', 'black', 'red']),
  _FQ(sentence: 'I like to ___ books before sleeping.', correct: 'read', wrong: ['eat', 'draw', 'sing']),
  _FQ(sentence: 'He ___ a glass of water every morning.', correct: 'drinks', wrong: ['eats', 'sleeps', 'runs']),
  _FQ(sentence: 'The dog is very ___. It never bites.', correct: 'friendly', wrong: ['angry', 'hungry', 'sleepy']),
  _FQ(sentence: 'We ___ football in the park on Sunday.', correct: 'play', wrong: ['eat', 'sleep', 'write']),
  _FQ(sentence: 'My mother ___ delicious food every day.', correct: 'cooks', wrong: ['builds', 'drives', 'paints']),
  _FQ(sentence: 'The sun ___ in the east every morning.', correct: 'rises', wrong: ['sets', 'falls', 'rests']),
  _FQ(sentence: 'Birds ___ in the sky above us.', correct: 'fly', wrong: ['swim', 'run', 'walk']),
  _FQ(sentence: 'I feel ___ after a good night\'s sleep.', correct: 'fresh', wrong: ['tired', 'sick', 'bored']),
  _FQ(sentence: 'He is ___ than his brother.', correct: 'taller', wrong: ['tall', 'tallest', 'tallness']),
  _FQ(sentence: 'She speaks English very ___.', correct: 'clearly', wrong: ['loud', 'fast', 'slow']),
];

const _level2 = [
  _FQ(sentence: 'She was ___ when she heard the good news.', correct: 'thrilled', wrong: ['bored', 'worried', 'confused']),
  _FQ(sentence: 'He made a ___ decision to change his career.', correct: 'bold', wrong: ['weak', 'silly', 'random']),
  _FQ(sentence: 'The athlete showed great ___ during the long race.', correct: 'endurance', wrong: ['beauty', 'silence', 'patience']),
  _FQ(sentence: 'She ___ her mistake and apologized sincerely.', correct: 'acknowledged', wrong: ['ignored', 'celebrated', 'repeated']),
  _FQ(sentence: 'The meeting was ___ due to the heavy rain.', correct: 'cancelled', wrong: ['started', 'enjoyed', 'planned']),
  _FQ(sentence: 'Reading regularly helps ___ your vocabulary.', correct: 'expand', wrong: ['reduce', 'forget', 'hide']),
  _FQ(sentence: 'He was very ___ about finishing the project on time.', correct: 'anxious', wrong: ['happy', 'lazy', 'creative']),
  _FQ(sentence: 'The company ___ its profits by twenty percent last year.', correct: 'increased', wrong: ['forgot', 'painted', 'cleaned']),
  _FQ(sentence: 'She has a very ___ personality — everyone loves her.', correct: 'charming', wrong: ['boring', 'rude', 'quiet']),
  _FQ(sentence: 'The instructions were too ___ to follow.', correct: 'complex', wrong: ['easy', 'short', 'colorful']),
  _FQ(sentence: 'He ___ every day to stay fit and healthy.', correct: 'exercises', wrong: ['sleeps', 'cries', 'argues']),
  _FQ(sentence: 'She ___ a deep breath before starting her speech.', correct: 'took', wrong: ['gave', 'lost', 'broke']),
];

const _level3 = [
  _FQ(sentence: 'The scientist made a ___ discovery that changed medicine forever.', correct: 'groundbreaking', wrong: ['ordinary', 'forgettable', 'mediocre']),
  _FQ(sentence: 'His speech was so ___ that the entire audience was deeply moved.', correct: 'eloquent', wrong: ['boring', 'confusing', 'repetitive']),
  _FQ(sentence: 'The government implemented ___ measures to tackle rising pollution.', correct: 'stringent', wrong: ['optional', 'relaxed', 'temporary']),
  _FQ(sentence: 'She showed ___ courage in the face of extreme adversity.', correct: 'remarkable', wrong: ['minimal', 'ordinary', 'questionable']),
  _FQ(sentence: 'The new policy was met with ___ opposition from the public.', correct: 'fierce', wrong: ['mild', 'quiet', 'unexpected']),
  _FQ(sentence: 'He has an ___ ability to solve complex mathematical problems.', correct: 'innate', wrong: ['ordinary', 'learned', 'average']),
  _FQ(sentence: 'The evidence presented was ___ and could not be disputed.', correct: 'irrefutable', wrong: ['weak', 'confusing', 'incomplete']),
  _FQ(sentence: 'She remained ___ despite receiving tremendous criticism online.', correct: 'resilient', wrong: ['broken', 'silent', 'cheerful']),
  _FQ(sentence: 'The economic ___ affected millions of people across the world.', correct: 'recession', wrong: ['growth', 'holiday', 'discovery']),
  _FQ(sentence: 'His ___ approach to problem-solving impressed the entire leadership team.', correct: 'pragmatic', wrong: ['emotional', 'impulsive', 'theoretical']),
  _FQ(sentence: 'The situation was ___; it required immediate professional attention.', correct: 'critical', wrong: ['relaxed', 'amusing', 'trivial']),
  _FQ(sentence: 'She demonstrated ___ leadership qualities during the prolonged crisis.', correct: 'exemplary', wrong: ['poor', 'average', 'casual']),
];

List<_FQ> _questionsForLevel(int level) {
  if (level == 2) return _level2;
  if (level == 3) return _level3;
  return _level1;
}

String _levelName(int level) {
  if (level == 2) return 'Medium';
  if (level == 3) return 'Hard';
  return 'Easy';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class FillBlanksScreen extends StatefulWidget {
  final int level;
  const FillBlanksScreen({super.key, this.level = 1});

  @override
  State<FillBlanksScreen> createState() => _FillBlanksScreenState();
}

class _FillBlanksScreenState extends State<FillBlanksScreen>
    with TickerProviderStateMixin {
  late List<_FQ> _questions;
  late List<List<String>> _shuffledOpts;
  int _qIndex = 0;
  int _score = 0;
  String? _selected;
  bool _answered = false;
  bool _done = false;

  late AnimationController _cardCtrl;
  late Animation<double> _cardAnim;

  @override
  void initState() {
    super.initState();
    final pool = List<_FQ>.from(_questionsForLevel(widget.level))..shuffle(Random());
    _questions = pool.take(10).toList();
    _shuffledOpts = _questions.map((q) => ([q.correct, ...q.wrong]..shuffle(Random()))).toList();

    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _cardAnim = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardCtrl.forward();
  }

  @override
  void dispose() {
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
  }

  Future<void> _next() async {
    if (_qIndex + 1 >= _questions.length) {
      await GameProgressService.instance.saveResult('fill', widget.level, _score, _questions.length);
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
    final pool = List<_FQ>.from(_questionsForLevel(widget.level))..shuffle(Random());
    setState(() {
      _questions = pool.take(10).toList();
      _shuffledOpts = _questions.map((q) => ([q.correct, ...q.wrong]..shuffle(Random()))).toList();
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

  static const _cardColors = [Color(0xFF43E97B), Color(0xFF38F9D7)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(
          'Level ${widget.level} — Fill in the Blanks',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('$_score/${_questions.length}',
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: _done ? _buildResult() : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    final q = _questions[_qIndex];
    final opts = _shuffledOpts[_qIndex];
    final parts = q.sentence.split('___');
    final filled = _selected ?? '______';
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
        const SizedBox(height: 20),

        FadeTransition(
          opacity: _cardAnim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero).animate(_cardAnim),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: _cardColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: _cardColors[0].withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_levelName(widget.level)} — Complete the sentence',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6, fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(text: parts[0]),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _answered
                                    ? (_selected == q.correct
                                        ? Colors.green.shade700
                                        : Colors.red.shade700)
                                    : Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _answered ? _selected! : filled,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (parts.length > 1) TextSpan(text: parts[1]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: opts.map((opt) => _OptionTile(
              text: opt,
              isCorrect: opt == q.correct,
              isSelected: opt == _selected,
              answered: _answered,
              onTap: () => _select(opt),
            )).toList(),
          ),
        ),
        if (_answered)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _qIndex + 1 >= _questions.length ? 'See Results' : 'Next Question →',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
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
            const Icon(Icons.edit_note_rounded, size: 56, color: Color(0xFF43E97B)),
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
            const Text('Fill in the Blanks Complete!',
                style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('$_score out of ${_questions.length} correct',
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

// ── Option tile ───────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String text;
  final bool isCorrect, isSelected, answered;
  final VoidCallback onTap;

  const _OptionTile({
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
            Expanded(child: Text(text,
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
