import 'package:supabase_flutter/supabase_flutter.dart';

class FriendService {
  final _client = Supabase.instance.client;

  String get _myId => _client.auth.currentUser!.id;

  Future<void> sendRequest(String receiverId) async {
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
    final resp = await _client
        .from('friendships')
        .select('id, requester_id, receiver_id, requester:profiles!requester_id(id,name,avatar_url), receiver:profiles!receiver_id(id,name,avatar_url)')
        .or('requester_id.eq.$_myId,receiver_id.eq.$_myId')
        .eq('status', 'accepted');
    return List<Map<String, dynamic>>.from(resp);
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
