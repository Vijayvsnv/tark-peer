import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';

class DirectCallService {
  DirectCallService._();
  static final DirectCallService instance = DirectCallService._();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingCalls => _controller.stream;

  RealtimeChannel? _channel;

  void subscribe() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _channel != null) return;
    _channel = Supabase.instance.client
        .channel('direct:$userId')
        .onBroadcast(
          event: 'incoming_call',
          callback: (payload) {
            final raw = payload['payload'];
            final data = (raw is Map)
                ? raw.cast<String, dynamic>()
                : (payload as Map).cast<String, dynamic>();
            _controller.add(data);
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<Map<String, dynamic>?> initiateCall(String receiverId) async {
    final token = AuthService().accessToken;
    if (token == null) return null;
    try {
      final resp = await http.post(
        Uri.parse('$kBackendUrl/call/direct'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'receiver_id': receiverId}),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
