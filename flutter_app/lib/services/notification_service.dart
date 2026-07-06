import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

class NotificationService {
  static final instance = NotificationService._();
  NotificationService._();

  final _db = Supabase.instance.client;
  final _auth = AuthService();

  String? get _uid => _auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> getAll() async {
    if (_uid == null) return [];
    try {
      final data = await _db
          .from('notifications')
          .select()
          .eq('user_id', _uid!)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  Future<int> getUnreadCount() async {
    if (_uid == null) return 0;
    try {
      final data = await _db
          .from('notifications')
          .select()
          .eq('user_id', _uid!)
          .eq('is_read', false);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAllRead() async {
    if (_uid == null) return;
    try {
      await _db
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _uid!)
          .eq('is_read', false);
    } catch (_) {}
  }

  Future<void> deleteById(String id) async {
    try {
      await _db.from('notifications').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> insertMissedCall({
    required String callerName,
    required String callerId,
    String? callerAvatar,
  }) async {
    if (_uid == null) return;
    try {
      await _db.from('notifications').insert({
        'user_id': _uid,
        'type': 'missed_call',
        'title': 'Missed Call',
        'body': '$callerName tried to call you',
        'data': {
          'caller_id': callerId,
          'caller_name': callerName,
          if (callerAvatar != null) 'caller_avatar': callerAvatar,
        },
      });
    } catch (_) {}
  }
}
