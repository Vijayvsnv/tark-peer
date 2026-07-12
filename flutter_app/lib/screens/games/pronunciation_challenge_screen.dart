import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import '../../services/game_progress_service.dart';

// ── Word pools ────────────────────────────────────────────────────────────────

const _easy = [
  'Apple', 'Beautiful', 'Challenge', 'Develop', 'Education',
  'Family', 'Growth', 'Hospital', 'Imagine', 'Journey',
  'Knowledge', 'Language', 'Morning', 'Navigate', 'Opportunity',
  'Practice', 'Question', 'Respect', 'Successful', 'Together',
  'Understand', 'Vocabulary', 'Wonderful', 'Excellent', 'Positive',
  'Communicate', 'Confident', 'Determined', 'Experience', 'Friendship',
];

const _medium = [
  'Communication', 'Pronunciation', 'Enthusiasm', 'Incredible',
  'Persistence', 'Achievement', 'Motivation', 'Imagination',
  'Determination', 'Organization', 'Responsibility', 'Collaboration',
  'Environmental', 'Satisfaction', 'Comfortable', 'Characteristic',
  'Revolutionary', 'Independence', 'Conversation', 'Professional',
  'Comprehension', 'Demonstration', 'Significantly', 'International',
  'Unfortunately', 'Underestimate', 'Experimental', 'Approximately',
  'Establishment', 'Contemplation',
];

const _hard = [
  'Conscientious', 'Simultaneous', 'Philosophical', 'Miscellaneous',
  'Psychological', 'Sophisticated', 'Electromagnetic', 'Rehabilitation',
  'Mediterranean', 'Extraordinary', 'Unprecedented', 'Circumstantial',
  'Predominantly', 'Metamorphosis', 'Photosynthesis', 'Bureaucratic',
  'Hierarchical', 'Serendipitous', 'Prerequisite', 'Extraterrestrial',
  'Cardiovascular', 'Infrastructure', 'Architectural', 'Procrastination',
  'Unnecessarily', 'Heterogeneous', 'Anthropomorphic', 'Disproportionate',
  'Multidimensional', 'Unambiguously',
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

class PronunciationChallengeScreen extends StatefulWidget {
  final int level;
  const PronunciationChallengeScreen({super.key, this.level = 1});

  @override
  State<PronunciationChallengeScreen> createState() =>
      _PronunciationChallengeScreenState();
}

class _PronunciationChallengeScreenState
    extends State<PronunciationChallengeScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _stt = SpeechToText();

  late List<String> _shuffled;
  int _index = 0;
  int _score = 0;
  final int _total = 10;

  bool _sttAvailable = false;
  bool _listening = false;
  bool _answered = false;
  bool _done = false;
  bool _correct = false;
  String _heard = '';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _shuffled = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.18)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initStt();
  }

  Future<void> _initStt() async {
    final ok = await _stt.initialize(
      onError: (_) => setState(() => _listening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _sttAvailable = ok);
  }

  @override
  void dispose() {
    _stt.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_sttAvailable || _listening || _answered) return;
    setState(() { _listening = true; _heard = ''; });
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          _checkAnswer(result.recognizedWords);
        } else {
          if (mounted) setState(() => _heard = result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 7),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
    );
  }

  void _checkAnswer(String heard) {
    final expected = _shuffled[_index].toLowerCase().trim();
    final got = heard.toLowerCase().trim();
    final correct = got == expected ||
        got.contains(expected) ||
        _similarity(expected, got) >= 0.8;
    setState(() {
      _listening = false;
      _answered = true;
      _correct = correct;
      _heard = heard.isEmpty ? '(nothing heard)' : heard;
      if (correct) _score++;
    });
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    int matches = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] == b[i]) matches++;
    }
    return matches / max(a.length, b.length);
  }

  Future<void> _next() async {
    if (_index + 1 >= _total) {
      await GameProgressService.instance.saveResult('pronun', widget.level, _score, _total);
      AnalyticsService.instance.logGamePlayed('pronun', widget.level, _score);
      setState(() => _done = true);
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _correct = false;
      _heard = '';
    });
  }

  void _restart() {
    setState(() {
      _shuffled = (List<String>.from(_poolForLevel(widget.level))..shuffle(Random())).take(_total).toList();
      _index = 0;
      _score = 0;
      _answered = false;
      _correct = false;
      _done = false;
      _heard = '';
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(
          'Level ${widget.level} — Pronunciation',
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
    final word = _shuffled[_index];
    final progress = (_index + 1) / _total;

    return Column(
      children: [
        LinearProgressIndicator(value: progress, backgroundColor: kSurface, color: kPrimary, minHeight: 4),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Word ${_index + 1} of $_total',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              Text('Score: $_score', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
            ],
          ),
        ),
        const Spacer(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: const Color(0xFF11998E).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                Text('${_levelName(widget.level)} — Say this word aloud',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),
                Text(
                  word,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: word.length > 12 ? 28 : 40,
                    fontWeight: FontWeight.w800, letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${word.length} letters',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        if (_answered)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _correct ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _correct ? Colors.green : Colors.red),
              ),
              child: Row(
                children: [
                  Icon(_correct ? Icons.check_circle : Icons.cancel,
                      color: _correct ? Colors.green : Colors.red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _correct ? 'Great pronunciation!' : 'Try again next time',
                          style: TextStyle(
                            color: _correct ? const Color(0xFF166534) : const Color(0xFF991B1B),
                            fontWeight: FontWeight.bold, fontSize: 13,
                          ),
                        ),
                        if (_heard.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('You said: "$_heard"',
                              style: TextStyle(
                                color: _correct ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                fontSize: 12,
                              )),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 32),

        if (!_answered) ...[
          if (!_sttAvailable) ...[
            const Text('Speech recognition not available on this device',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _next,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: kBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    foregroundColor: kTextSecondary,
                  ),
                  child: Text(
                    _index + 1 >= _total ? 'See Results' : 'Skip →',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ] else
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(
                scale: _listening ? _pulse.value : 1.0, child: child,
              ),
              child: GestureDetector(
                onTap: _startListening,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? Colors.red : kPrimary,
                    boxShadow: [BoxShadow(
                      color: (_listening ? Colors.red : kPrimary).withOpacity(0.35),
                      blurRadius: 20, spreadRadius: 4,
                    )],
                  ),
                  child: Icon(
                    _listening ? Icons.mic : Icons.mic_none_rounded,
                    color: Colors.white, size: 36,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _listening ? 'Listening...' : 'Tap mic and speak',
            style: TextStyle(
              color: _listening ? Colors.red : kTextSecondary,
              fontSize: 13,
              fontWeight: _listening ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (_listening && _heard.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"$_heard"', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
          ],
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _index + 1 >= _total ? 'See Results' : 'Next Word →',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

        const Spacer(),
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
            const Icon(Icons.record_voice_over_rounded, size: 56, color: Color(0xFF11998E)),
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
            const Text('Challenge Complete!',
                style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('$_score out of $_total correct',
                style: const TextStyle(color: kTextSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _score >= 8 ? 'Excellent pronunciation!' : _score >= 5 ? 'Good job!' : 'Keep practicing!',
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
