import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'auth_service.dart';

class MessageService {
  final _db = Supabase.instance.client;

  String get _myId => _db.auth.currentUser!.id;

  Future<List<Map<String, dynamic>>> fetchMessages(String friendId) async {
    final rows = await _db
        .from('messages')
        .select()
        .or('and(sender_id.eq.$_myId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$_myId)')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getLastMessage(String friendId) async {
    final rows = await _db
        .from('messages')
        .select()
        .or('and(sender_id.eq.$_myId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$_myId)')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> sendMessage(String receiverId, String content) async {
    await _db.from('messages').insert({
      'sender_id': _myId,
      'receiver_id': receiverId,
      'content': content,
    });

    // Push notification to receiver (fire-and-forget)
    _notifyMessage(receiverId, content);
  }

  void _notifyMessage(String receiverId, String content) {
    final token = AuthService().accessToken;
    if (token == null) return;
    http.post(
      Uri.parse('$kBackendUrl/notify/message'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'receiver_id': receiverId, 'preview': content}),
    ).catchError((_) {});
  }

  Future<void> markRead(String friendId) async {
    await _db
        .from('messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('sender_id', friendId)
        .eq('receiver_id', _myId)
        .isFilter('read_at', null);
  }

  RealtimeChannel subscribeToMessages(String friendId, void Function() onNew) {
    final channel = _db.channel('messages_${_myId}_$friendId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => onNew(),
        )
        .subscribe();
    return channel;
  }
}
