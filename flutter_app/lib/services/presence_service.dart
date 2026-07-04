import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  final _db = Supabase.instance.client;
  RealtimeChannel? _channel;

  String? get _myId => _db.auth.currentUser?.id;

  Future<void> setStatus(String status) async {
    final id = _myId;
    if (id == null) return;
    await _db.from('user_presence').upsert({
      'user_id': id,
      'status': status,
      'last_seen': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setOnline() => setStatus('online');
  Future<void> setOffline() => setStatus('offline');
  Future<void> setInCall() => setStatus('in_call');

  Stream<Map<String, String>> watchPresence(List<String> friendIds) {
    if (friendIds.isEmpty) return Stream.value({});
    final controller = StreamController<Map<String, String>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _db
            .from('user_presence')
            .select('user_id, status')
            .inFilter('user_id', friendIds);
        final map = <String, String>{
          for (final r in rows) r['user_id'] as String: r['status'] as String? ?? 'offline',
        };
        if (!controller.isClosed) controller.add(map);
      } catch (_) {}
    }

    fetch();

    _channel = _db.channel('presence_watch')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_presence',
        callback: (_) => fetch(),
      )
      ..subscribe();

    return controller.stream;
  }

  void dispose() {
    if (_channel != null) {
      _db.removeChannel(_channel!);
      _channel = null;
    }
  }
}
