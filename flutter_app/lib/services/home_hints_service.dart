import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time first-run hints on the home screen:
///  - "Tap here" arrow above the Tark Here button
///  - Pulse dots on the Learn and Games bottom tabs
///
/// Each hint is a boolean flag stored in SharedPreferences. Once dismissed,
/// it stays gone across app restarts (local only — uninstall resets it).
class HomeHintsService {
  static final _instance = HomeHintsService._();
  factory HomeHintsService() => _instance;
  HomeHintsService._();

  static const _tarkKey = 'hint_tark_here_seen_v1';
  static const _learnKey = 'hint_learn_tab_seen_v1';
  static const _gamesKey = 'hint_games_tab_seen_v1';

  /// True once the user has dismissed that hint.
  final ValueNotifier<bool> tarkSeen = ValueNotifier(false);
  final ValueNotifier<bool> learnSeen = ValueNotifier(false);
  final ValueNotifier<bool> gamesSeen = ValueNotifier(false);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    tarkSeen.value = prefs.getBool(_tarkKey) ?? false;
    learnSeen.value = prefs.getBool(_learnKey) ?? false;
    gamesSeen.value = prefs.getBool(_gamesKey) ?? false;
  }

  Future<void> markTarkSeen() => _mark(_tarkKey, tarkSeen);
  Future<void> markLearnSeen() => _mark(_learnKey, learnSeen);
  Future<void> markGamesSeen() => _mark(_gamesKey, gamesSeen);

  Future<void> _mark(String key, ValueNotifier<bool> notifier) async {
    if (notifier.value) return;
    notifier.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
