import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart';

class RatingService {
  final _auth = AuthService();

  Future<bool> rate({
    required String channelName,
    required String ratedUserId,
    required int stars,
  }) async {
    final token = _auth.accessToken;
    if (token == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('$kBackendUrl/call/rate'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'channel_name': channelName,
          'rated_user_id': ratedUserId,
          'stars': stars,
        }),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
