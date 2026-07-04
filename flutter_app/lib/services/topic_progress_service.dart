import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/topics.dart';

/// Tracks which Learn-tab topics the user has "practiced" (tapped Use in Next
/// Call on). Stored as a Set of `"levelNum:topicIndex"` strings in
/// SharedPreferences. Level N+1 unlocks when every topic in Level N is
/// practiced. Level 1 is always unlocked.
class TopicProgressService {
  static final _instance = TopicProgressService._();
  factory TopicProgressService() => _instance;
  TopicProgressService._();

  static const _prefsKey = 'practiced_topics';

  /// Reactive set — screens listen to this and rebuild automatically.
  final ValueNotifier<Set<String>> practiced = ValueNotifier(<String>{});

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    practiced.value = list.toSet();
  }

  String _key(int level, int index) => '$level:$index';

  bool isPracticed(int level, int index) =>
      practiced.value.contains(_key(level, index));

  Future<void> markPracticed(int level, int index) async {
    final key = _key(level, index);
    if (practiced.value.contains(key)) return;
    practiced.value = {...practiced.value, key};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, practiced.value.toList());
  }

  int practicedCount(TopicLevel level) {
    var count = 0;
    for (var i = 0; i < level.topics.length; i++) {
      if (isPracticed(level.level, i)) count++;
    }
    return count;
  }

  bool isLevelComplete(TopicLevel level) =>
      practicedCount(level) >= level.topics.length;

  /// Level at [index] is unlocked iff all previous levels are complete.
  bool isLevelUnlocked(int index) {
    if (index == 0) return true;
    for (var i = 0; i < index; i++) {
      if (!isLevelComplete(kTopicLevels[i])) return false;
    }
    return true;
  }
}
