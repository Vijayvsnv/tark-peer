import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart';

class AiDailyLimitException implements Exception {
  final int limit;
  const AiDailyLimitException(this.limit);
}

class AiUnavailableException implements Exception {
  const AiUnavailableException();
}

class AiSession {
  final String sessionId;
  final int maxSeconds;
  final String partnerName;

  const AiSession({
    required this.sessionId,
    required this.maxSeconds,
    required this.partnerName,
  });
}

class AiPartnerService {
  final _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.accessToken ?? ""}',
      };

  Future<AiSession> startSession() async {
    final resp = await http.post(
      Uri.parse('$kBackendUrl/ai/start'),
      headers: _headers,
    );
    if (resp.statusCode == 503) throw const AiUnavailableException();
    if (resp.statusCode == 429) {
      throw AiDailyLimitException(kAiDailyLimit);
    }
    if (resp.statusCode != 200) {
      throw Exception('Failed to start AI session: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return AiSession(
      sessionId: body['session_id'] as String,
      maxSeconds: body['max_seconds'] as int? ?? kAiMaxCallSeconds,
      partnerName: body['partner_name'] as String? ?? kAiPartnerName,
    );
  }

  /// Returns null on network/timeout error — caller shows retry state.
  Future<String?> chat(
    String sessionId,
    String userText,
    List<Map<String, String>> history,
  ) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$kBackendUrl/ai/chat'),
            headers: _headers,
            body: jsonEncode({
              'session_id': sessionId,
              'user_text': userText,
              'history': history,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['reply'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget safe — caller does not need to await.
  Future<Map<String, dynamic>?> endSession(
    String sessionId,
    List<Map<String, String>> transcript,
    int durationSeconds,
  ) async {
    try {
      final resp = await http.post(
        Uri.parse('$kBackendUrl/ai/end'),
        headers: _headers,
        body: jsonEncode({
          'session_id': sessionId,
          'transcript': transcript,
          'duration_seconds': durationSeconds,
        }),
      );
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['feedback'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Check daily quota without starting a session.
  Future<({int used, int limit, int remaining})> getQuota() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBackendUrl/ai/quota'),
        headers: _headers,
      );
      if (resp.statusCode != 200) {
        return (used: 0, limit: kAiDailyLimit, remaining: kAiDailyLimit);
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (
        used: body['used'] as int? ?? 0,
        limit: body['limit'] as int? ?? kAiDailyLimit,
        remaining: body['remaining'] as int? ?? kAiDailyLimit,
      );
    } catch (_) {
      return (used: 0, limit: kAiDailyLimit, remaining: kAiDailyLimit);
    }
  }
}
