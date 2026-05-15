import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
import '../models/match_event.dart';

enum MatchState { idle, waiting, matched, ended }

class MatchService {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  MatchState _state = MatchState.idle;

  Stream<Map<String, dynamic>> get events => _controller.stream;
  MatchState get state => _state;

  Future<void> connect(String token) async {
    final uri = Uri.parse('$kWsUrl?token=$token');
    _channel = WebSocketChannel.connect(uri);
    _state = MatchState.waiting;

    _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          if (type == 'matched') _state = MatchState.matched;
          if (type == 'call_ended') _state = MatchState.ended;
          _controller.add(msg);
        } catch (_) {}
      },
      onDone: () {
        _state = MatchState.ended;
        _controller.add({'type': 'call_ended', 'reason': 'disconnect'});
      },
      onError: (_) {
        _state = MatchState.ended;
        _controller.add({'type': 'error', 'message': 'Connection lost'});
      },
    );
  }

  void sendCancel() => _send({'type': 'cancel'});
  void sendEndCall() => _send({'type': 'end_call'});
  void sendPing() => _send({'type': 'ping'});

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _state = MatchState.idle;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
