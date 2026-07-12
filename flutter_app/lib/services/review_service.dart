import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();

  // Set this flag to true before navigating home after a qualifying call.
  // HomeScreen reads and clears it on first frame to trigger maybeAsk.
  static bool pendingCheck = false;

  static const _keyCallCount = 'successful_calls_count';
  static const _keyShown = 'review_prompt_shown_v1';

  Future<void> recordSuccessfulCall(int durationSeconds) async {
    try {
      if (durationSeconds < 120) return;
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_keyCallCount) ?? 0) + 1;
      await prefs.setInt(_keyCallCount, count);
    } catch (_) {}
  }

  Future<void> maybeAsk(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyShown) == true) return;
      final count = prefs.getInt(_keyCallCount) ?? 0;
      if (count < 3) return;
      final available = await InAppReview.instance.isAvailable();
      if (!available) return;
      await InAppReview.instance.requestReview();
      await prefs.setBool(_keyShown, true);
    } catch (_) {}
  }
}
