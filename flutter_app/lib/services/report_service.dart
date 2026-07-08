import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart';

class ReportService {
  final _auth = AuthService();

  Future<bool> reportUser({
    required String reportedId,
    String? roomId,
    required String reason,
    String? details,
  }) async {
    final token = _auth.accessToken;
    if (token == null) return false;
    try {
      final body = <String, dynamic>{
        'reported_id': reportedId,
        'reason': reason,
      };
      if (roomId != null) body['room_id'] = roomId;
      if (details != null && details.isNotEmpty) body['details'] = details;

      final resp = await http.post(
        Uri.parse('$kBackendUrl/report'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
