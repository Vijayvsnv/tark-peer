import 'package:supabase_flutter/supabase_flutter.dart';

class BlockService {
  final _client = Supabase.instance.client;

  String get _myId => _client.auth.currentUser!.id;

  Future<void> blockUser(String userId) async {
    await _client.from('blocks').insert({
      'blocker_id': _myId,
      'blocked_id': userId,
    });
    // Remove any friendship between the two (best-effort, RLS allows deleting own rows)
    try {
      await _client.from('friendships').delete().or(
        'and(requester_id.eq.$_myId,receiver_id.eq.$userId),'
        'and(requester_id.eq.$userId,receiver_id.eq.$_myId)',
      );
    } catch (_) {}
  }

  Future<void> unblockUser(String userId) async {
    await _client
        .from('blocks')
        .delete()
        .eq('blocker_id', _myId)
        .eq('blocked_id', userId);
  }

  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    // Step 1: rows where I am the blocker
    final blocks = await _client
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', _myId);
    final blockRows = List<Map<String, dynamic>>.from(blocks);
    if (blockRows.isEmpty) return [];

    final blockedIds = blockRows.map((b) => b['blocked_id'] as String).toList();

    // Step 2: batch-fetch profiles (immutable-map spread pattern)
    final profiles = await _client
        .from('profiles')
        .select('id, name, avatar_url')
        .inFilter('id', blockedIds);
    final profileMap = <String, Map<String, dynamic>>{};
    for (final p in List<Map<String, dynamic>>.from(profiles)) {
      profileMap[p['id'] as String] = p;
    }

    return blockedIds.map((id) {
      final row = blockRows.firstWhere((b) => b['blocked_id'] == id);
      return <String, dynamic>{...row, 'profile': profileMap[id]};
    }).toList();
  }

  Future<bool> isBlocked(String userId) async {
    try {
      final resp = await _client
          .from('blocks')
          .select('id')
          .or(
            'and(blocker_id.eq.$_myId,blocked_id.eq.$userId),'
            'and(blocker_id.eq.$userId,blocked_id.eq.$_myId)',
          )
          .maybeSingle();
      return resp != null;
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> getBlockedUserIds() async {
    try {
      final resp = await _client
          .from('blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$_myId,blocked_id.eq.$_myId');
      final rows = List<Map<String, dynamic>>.from(resp);
      final ids = <String>{};
      for (final row in rows) {
        final blocker = row['blocker_id'] as String;
        final blocked = row['blocked_id'] as String;
        if (blocker != _myId) ids.add(blocker);
        if (blocked != _myId) ids.add(blocked);
      }
      return ids;
    } catch (_) {
      return {};
    }
  }
}
