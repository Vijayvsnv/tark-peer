import 'package:supabase_flutter/supabase_flutter.dart';

class FriendService {
  final _client = Supabase.instance.client;

  String get _myId => _client.auth.currentUser!.id;

  Future<void> sendRequest(String receiverId) async {
    // If the other person already sent us a request, accept that instead of
    // creating a duplicate row (prevents both-sides-sent → 2 friend entries).
    final reverse = await _client
        .from('friendships')
        .select('id, status')
        .eq('requester_id', receiverId)
        .eq('receiver_id', _myId)
        .maybeSingle();

    if (reverse != null) {
      if (reverse['status'] == 'pending') {
        await acceptRequest(reverse['id'] as String);
      }
      return;
    }

    await _client.from('friendships').insert({
      'requester_id': _myId,
      'receiver_id': receiverId,
      'status': 'pending',
    });
  }

  Future<void> acceptRequest(String friendshipId) async {
    await _client
        .from('friendships')
        .update({'status': 'accepted', 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', friendshipId);
  }

  Future<void> rejectRequest(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
  }

  Future<String?> getFriendshipStatus(String otherId) async {
    try {
      final resp = await _client
          .from('friendships')
          .select('status')
          .or('and(requester_id.eq.$_myId,receiver_id.eq.$otherId),and(requester_id.eq.$otherId,receiver_id.eq.$_myId)')
          .maybeSingle();
      return resp?['status'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFriends() async {
    // Step 1: fetch accepted friendship rows (both directions)
    final resp = await _client
        .from('friendships')
        .select('id, requester_id, receiver_id')
        .or('requester_id.eq.$_myId,receiver_id.eq.$_myId')
        .eq('status', 'accepted');

    final friendships = List<Map<String, dynamic>>.from(resp);
    if (friendships.isEmpty) return [];

    // Step 2: collect unique partner IDs (deduplicates both-sides-sent case)
    final partnerIds = <String>[];
    final seen = <String>{};
    for (final f in friendships) {
      final pid = f['requester_id'] == _myId ? f['receiver_id'] : f['requester_id'];
      if (pid != null && seen.add(pid as String)) partnerIds.add(pid);
    }

    // Step 3: batch fetch partner profiles
    final profiles = await _client
        .from('profiles')
        .select('id, name, avatar_url')
        .inFilter('id', partnerIds);

    final profileMap = <String, Map<String, dynamic>>{};
    for (final p in List<Map<String, dynamic>>.from(profiles)) {
      profileMap[p['id'] as String] = p;
    }

    // Step 4: one entry per unique partner with their profile attached
    return partnerIds.map((pid) {
      final f = friendships.firstWhere(
        (row) => row['requester_id'] == pid || row['receiver_id'] == pid,
      );
      return <String, dynamic>{...f, 'partner_profile': profileMap[pid]};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final resp = await _client
        .from('friendships')
        .select('id, requester_id, requester:profiles!requester_id(id,name,avatar_url), created_at')
        .eq('receiver_id', _myId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(resp);
  }

  Future<int> getPendingCount() async {
    final resp = await _client
        .from('friendships')
        .select('id')
        .eq('receiver_id', _myId)
        .eq('status', 'pending')
        .count(CountOption.exact);
    return resp.count ?? 0;
  }
}
