// Matchmaking client.
//
// Architecture (Option C):
//   * Subscribe to Supabase Realtime channel `user:{my_id}` BEFORE opening
//     the WebSocket.  This is how match events reach us — the backend
//     broadcasts to that channel and any client instance receives it,
//     regardless of which backend pod produced the match.
//   * Open a thin WebSocket to /ws/match purely as queue presence: while
//     the socket is open the backend keeps us in the waiting pool; closing
//     the socket removes us.  No call-lifecycle signalling flows over it.
//
// Why the WS is still here: WebSocket close is the cheapest, most reliable
// way to express "this user gave up waiting" without a heartbeat loop.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';

enum MatchState { idle, waiting, matched, ended }

class MatchService {
  WebSocketChannel? _ws;
  RealtimeChannel? _userChannel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  MatchState _state = MatchState.idle;
  bool _matchReceived = false; // dedupe Realtime vs. WS fast-path

  Stream<Map<String, dynamic>> get events => _controller.stream;
  MatchState get state => _state;

  void _safeAdd(Map<String, dynamic> msg) {
    if (_controller.isClosed) return;
    // Deduplicate match events — backend sends one over Realtime AND one
    // over the WS fast-path.  Whichever wins, the other is a no-op.
    final type = msg['type'] as String?;
    if (type == 'matched') {
      if (_matchReceived) return;
      _matchReceived = true;
      _state = MatchState.matched;
    } else if (type == 'call_ended') {
      _state = MatchState.ended;
    }
    _controller.add(msg);
  }

  /// Subscribe to the user channel, then open the matching WebSocket.
  /// Returns once both legs are ready (or throws).
  Future<void> connect(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw StateError('connect() called without a signed-in Supabase user');
    }

    _matchReceived = false;

    // ── 1. Subscribe to user:{my_id} for the "matched" event ──
    await _subscribeUserChannel(user.id);

    // ── 2. Open the presence WebSocket ──
    final uri = Uri.parse('$kWsUrl?token=$token');
    debugPrint('[MatchService] WS connecting: $uri');
    _ws = WebSocketChannel.connect(uri);
    await _ws!.ready;
    debugPrint('[MatchService] WS ready');
    _state = MatchState.waiting;

    _ws!.stream.listen(
      (raw) {
        debugPrint('[MatchService] WS raw: $raw');
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _safeAdd(msg);
        } catch (e) {
          debugPrint('[MatchService] WS parse err: $e');
        }
      },
      onDone: () {
        debugPrint(
          '[MatchService] WS closed code=${_ws?.closeCode} reason=${_ws?.closeReason}',
        );
        // Don't synthesise a call_ended here — the matching screen has its
        // own logic to handle a closed-without-match WS (user cancelled,
        // network blip, etc).
      },
      onError: (Object error, StackTrace st) {
        debugPrint('[MatchService] WS error: $error\n$st');
        _safeAdd({'type': 'error', 'message': 'Connection lost: $error'});
      },
    );
  }

  Future<void> _subscribeUserChannel(String userId) async {
    final supabase = Supabase.instance.client;
    final topic = 'user:$userId';
    debugPrint('[MatchService] Subscribing to Realtime topic: $topic');

    final completer = Completer<void>();

    _userChannel = supabase.channel(topic)
      ..onBroadcast(
        event: 'matched',
        callback: (payload) {
          debugPrint('[MatchService] Realtime matched payload=$payload');
          _safeAdd({'type': 'matched', ...payload});
        },
      )
      ..subscribe((status, [error]) {
        debugPrint('[MatchService] Realtime status=$status err=$error');
        if (status == RealtimeSubscribeStatus.subscribed &&
            !completer.isCompleted) {
          completer.complete();
        } else if ((status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) &&
            !completer.isCompleted) {
          completer.completeError(
            StateError('Realtime subscribe failed: $status / $error'),
          );
        }
      });

    // Don't wait forever — if Realtime never confirms, fall back to WS.
    try {
      await completer.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('[MatchService] Realtime subscribe timeout — proceeding anyway');
    } catch (e) {
      debugPrint('[MatchService] Realtime subscribe error: $e — proceeding');
    }
  }

  void sendCancel() {
    debugPrint('[MatchService] sendCancel');
    _wsSend({'type': 'cancel'});
  }

  void sendPing() {
    _wsSend({'type': 'ping'});
  }

  void _wsSend(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('[MatchService] WS send failed: $e');
    }
  }

  /// Close the WebSocket + unsubscribe from Realtime, but keep the event
  /// stream open so listeners can still react to a final event.
  Future<void> disconnect() async {
    debugPrint('[MatchService] disconnect()');
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    final ch = _userChannel;
    _userChannel = null;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }

    _state = MatchState.idle;
  }

  void dispose() {
    disconnect();
    if (!_controller.isClosed) _controller.close();
  }
}
