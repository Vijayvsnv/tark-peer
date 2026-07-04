import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has completed the first-launch intro slides.
/// Stored locally — reset on uninstall.
class OnboardingService {
  static const _prefsKey = 'onboarding_seen_v1';

  Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
