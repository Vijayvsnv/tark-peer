import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/game_progress_service.dart';

// ── Sentence pools ────────────────────────────────────────────────────────────

const _easy = [
  'The cat is sitting on the mat.',
  'I drink water every morning.',
  'She has a red umbrella.',
  'He goes to work by bus.',
  'The children are very happy today.',
  'We eat dinner at seven o\'clock.',
  'My dog is black and white.',
  'She is wearing a blue dress.',
  'The book is on the table.',
  'He wakes up early every morning.',
  'It is a beautiful sunny day.',
  'I have a pen and a pencil.',
];

const _medium = [
  'The sun rises in the east every morning.',
  'She is learning to speak English every day.',
  'Practice makes a man perfect.',
  'He went to the market to buy some vegetables.',
  'The children are playing in the park.',
  'Knowledge is the most powerful weapon.',
  'We should always be kind to others.',
  'Hard work always leads to success.',
  'Reading books improves your vocabulary.',
  'Communication skills are very important in life.',
  'The dog is sitting near the door.',
  'She speaks English very fluently and confidently.',
  'Good habits lead to a healthy life.',
  'He studies for two hours every evening.',
  'They are working together on a new project.',
];

const _hard = [
  'Despite the heavy rainfall, the outdoor event was a remarkable success.',
  'The professor emphasized the importance of critical thinking in academic research.',
  'She demonstrated extraordinary patience while explaining the complex mathematical formula.',
  'The government implemented several stringent measures to reduce environmental pollution.',
  'He managed to overcome all obstacles and achieved his long-term professional goal.',
  'The new technology has the potential to revolutionize the way we communicate globally.',
  'Critical thinking and effective communication are essential skills in the modern workplace.',
  'The scientist conducted extensive research before publishing her groundbreaking discovery.',
  'Despite numerous setbacks, the team remained determined to complete the project on schedule.',
  'The economic recession had a profound impact on businesses across the entire country.',
  'She demonstrated remarkable resilience in the face of significant personal and professional challenges.',
  'Regular exercise and a balanced diet are fundamental to maintaining good overall health.',
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

double _speedForLevel(int level) {
  if (level == 3) return 0.42;
  if (level == 2) return 0.45;
  return 0.50;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class DictationScreen extends StatefulWidget {
  final int level;
  const DictationScreen({super.key, this.level = 1});

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final FlutterTts _tts = FlutterTts();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  late List<String> _shuffled;
  int _index = 0;
  int _score = 0;
  final int _total = 10;

  bool _playing = false;
  bool _answered = false;
  bool _done = false;
  bool _ttsReady = false;
  int _accuracy = 0;

  @override
  void initState() {
    super.initState();
    _shuffled = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_speedForLevel(widget.level));
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _tts.stop();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    if (_playing || !_ttsReady || _answered) return;
    setState(() => _playing = true);
    await _tts.speak(_shuffled[_index]);
  }

  Future<void> _stop() async {
    await _tts.stop();
    if (mounted) setState(() => _playing = false);
  }

  void _submit() {
    if (_answered) return;
    final typed = _controller.text.trim();
    if (typed.isEmpty) return;
    final acc = _calcAccuracy(_shuffled[_index], typed);
    setState(() {
      _answered = true;
      _accuracy = acc;
      if (acc >= 80) _score++;
    });
    _tts.stop();
    _focusNode.unfocus();
  }

  int _calcAccuracy(String original, String typed) {
    final orig = _normalize(original).split(' ');
    final inp = _normalize(typed).split(' ');
    int matched = 0;
    for (final w in inp) {
      if (orig.contains(w)) matched++;
    }
    return ((matched / orig.length) * 100).round().clamp(0, 100);
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  Future<void> _next() async {
    if (_index + 1 >= _total) {
      await GameProgressService.instance.saveResult('dict', widget.level, _score, _total);
      setState(() => _done = true);
      return;
    }
    _controller.clear();
    setState(() {
      _index++;
      _answered = false;
      _accuracy = 0;
    });
  }

  void _restart() {
    _controller.clear();
    setState(() {
      _shuffled = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();
      _index = 0;
      _score = 0;
      _answered = false;
      _done = false;
      _accuracy = 0;
    });
  }

  int get _stars {
    final pct = _score / _total;
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
          onPressed: () { _tts.stop(); context.pop(); },
        ),
        title: Text(
          'Level ${widget.level} — Dictation',
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
    final progress = (_index + 1) / _total;
    final sentence = _shuffled[_index];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          children: [
            LinearProgressIndicator(value: progress, backgroundColor: kSurface, color: kPrimary, minHeight: 4),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sentence ${_index + 1} of $_total',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  Text('Score: $_score', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Speaker card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF7971E), Color(0xFFFFD200)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFFF7971E).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    Text(
                      '${_levelName(widget.level)} — Listen and type what you hear',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _playing ? _stop : _speak,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 68, height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(_playing ? 0.4 : 0.25),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _playing ? Icons.stop_rounded : Icons.volume_up_rounded,
                          color: Colors.white, size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _playing ? 'Playing...' : 'Tap to listen',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    const Text('You can replay as many times as needed',
                        style: TextStyle(color: Colors.white60, fontSize: 11)),
                    if (_answered) ...[
                      const SizedBox(height: 14),
                      const Divider(color: Colors.white30),
                      const SizedBox(height: 8),
                      Text(
                        '"$sentence"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic, height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Text input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !_answered,
                maxLines: 3, minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: kTextPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Type what you heard...',
                  filled: true, fillColor: kSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kPrimary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Accuracy feedback
            if (_answered)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _accuracy >= 80
                        ? const Color(0xFFDCFCE7)
                        : _accuracy >= 50
                            ? const Color(0xFFFFF7CD)
                            : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _accuracy >= 80 ? Colors.green : _accuracy >= 50 ? Colors.orange : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _accuracy >= 80 ? Icons.check_circle : _accuracy >= 50 ? Icons.info : Icons.cancel,
                        color: _accuracy >= 80 ? Colors.green : _accuracy >= 50 ? Colors.orange : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Accuracy: $_accuracy% — '
                          '${_accuracy >= 80 ? 'Excellent!' : _accuracy >= 50 ? 'Good attempt!' : 'Keep practicing!'}',
                          style: TextStyle(
                            color: _accuracy >= 80
                                ? const Color(0xFF166534)
                                : _accuracy >= 50
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF991B1B),
                            fontSize: 13, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          _index + 1 >= _total ? 'See Results' : 'Next Sentence →',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF7971E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Submit Answer',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, size: 56, color: Color(0xFFF7971E)),
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
            const Text('Dictation Complete!',
                style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('$_score out of $_total correct (≥80% accuracy)',
                style: const TextStyle(color: kTextSecondary, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _score >= 8 ? 'Outstanding listener!' : _score >= 5 ? 'Good job!' : 'Keep practicing!',
              style: TextStyle(
                color: _score >= 5 ? kPrimary : kTextSecondary,
                fontSize: 15, fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
