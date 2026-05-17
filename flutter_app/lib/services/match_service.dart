import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  void _safeAdd(Map<String, dynamic> msg) {
    if (!_controller.isClosed) _controller.add(msg);
  }

  Future<void> connect(String token) async {
    final uri = Uri.parse('$kWsUrl?token=$token');
    debugPrint('[MatchService] Connecting to: $uri');

    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    debugPrint('[MatchService] WebSocket connected successfully');

    _state = MatchState.waiting;

    _channel!.stream.listen(
      (raw) {
        debugPrint('[MatchService] Raw: $raw');
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          debugPrint('[MatchService] type=$type');
          if (type == 'matched') _state = MatchState.matched;
          if (type == 'call_ended') _state = MatchState.ended;
          _safeAdd(msg);
        } catch (e) {
          debugPrint('[MatchService] Parse error: $e  raw=$raw');
        }
      },
      onDone: () {
        debugPrint(
          '[MatchService] Closed — code=${_channel?.closeCode} reason=${_channel?.closeReason}',
        );
        _state = MatchState.ended;
        _safeAdd({'type': 'call_ended', 'reason': 'disconnect'});
      },
      onError: (Object error, StackTrace st) {
        debugPrint('[MatchService] Error: $error\n$st');
        _state = MatchState.ended;
        _safeAdd({'type': 'error', 'message': 'Connection lost: $error'});
      },
    );
  }

  void sendCancel() {
    debugPrint('[MatchService] Sending cancel');
    _send({'type': 'cancel'});
  }

  void sendEndCall() {
    debugPrint('[MatchService] Sending end_call');
    _send({'type': 'end_call'});
  }

  void sendPing() {
    debugPrint('[MatchService] Sending ping');
    _send({'type': 'ping'});
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
      debugPrint('[MatchService] Sent: $msg');
    } catch (e) {
      debugPrint('[MatchService] Send failed: $e');
    }
  }

  // Only closes _channel — _controller stays open
  Future<void> disconnect() async {
    debugPrint('[MatchService] Disconnecting...');
    await _channel?.sink.close();
    _channel = null;
    _state = MatchState.idle;
    debugPrint('[MatchService] Disconnected');
  }

  // _controller only closed here, never in disconnect()
  void dispose() {
    disconnect();
    if (!_controller.isClosed) _controller.close();
  }
}
