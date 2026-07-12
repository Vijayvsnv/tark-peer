import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final _analytics = FirebaseAnalytics.instance;

  Future<void> logSignup() async {
    try {
      await _analytics.logSignUp(signUpMethod: 'email');
    } catch (_) {}
  }

  Future<void> logLogin() async {
    try {
      await _analytics.logLogin(loginMethod: 'email');
    } catch (_) {}
  }

  Future<void> logProfileCompleted() async {
    try {
      await _analytics.logEvent(name: 'profile_completed');
    } catch (_) {}
  }

  Future<void> logMatchStarted() async {
    try {
      await _analytics.logEvent(name: 'match_started');
    } catch (_) {}
  }

  Future<void> logMatchFound(int waitSeconds) async {
    try {
      await _analytics.logEvent(
        name: 'match_found',
        parameters: {'wait_seconds': waitSeconds},
      );
    } catch (_) {}
  }

  Future<void> logMatchTimeout() async {
    try {
      await _analytics.logEvent(name: 'match_timeout');
    } catch (_) {}
  }

  Future<void> logCallEnded(int durationSeconds, String reason) async {
    try {
      await _analytics.logEvent(
        name: 'call_ended',
        parameters: {'duration_seconds': durationSeconds, 'reason': reason},
      );
    } catch (_) {}
  }

  Future<void> logAiSessionStarted(String source) async {
    try {
      await _analytics.logEvent(
        name: 'ai_session_started',
        parameters: {'source': source},
      );
    } catch (_) {}
  }

  Future<void> logAiSessionEnded(int durationSeconds, int turns) async {
    try {
      await _analytics.logEvent(
        name: 'ai_session_ended',
        parameters: {'duration_seconds': durationSeconds, 'turns': turns},
      );
    } catch (_) {}
  }

  Future<void> logAiFeedbackShown(int score) async {
    try {
      await _analytics.logEvent(
        name: 'ai_feedback_shown',
        parameters: {'score': score},
      );
    } catch (_) {}
  }

  Future<void> logGamePlayed(String game, int level, int score) async {
    try {
      await _analytics.logEvent(
        name: 'game_played',
        parameters: {'game': game, 'level': level, 'score': score},
      );
    } catch (_) {}
  }

  Future<void> logRoomCreated(int size) async {
    try {
      await _analytics.logEvent(
        name: 'room_created',
        parameters: {'size': size},
      );
    } catch (_) {}
  }

  Future<void> logRoomJoined() async {
    try {
      await _analytics.logEvent(name: 'room_joined');
    } catch (_) {}
  }

  Future<void> logReportSubmitted() async {
    try {
      await _analytics.logEvent(name: 'report_submitted');
    } catch (_) {}
  }
}
