import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class ProfileService {
  final _client = Supabase.instance.client;

  Future<UserProfile?> getMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final resp = await _client.from('profiles').select().eq('id', user.id).single();
    return UserProfile.fromJson(resp);
  }

  Future<UserProfile?> updateProfile({
    String? name,
    int? age,
    String? gender,
    String? bio,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final updates = <String, dynamic>{
      if (name != null) 'name': name,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (bio != null) 'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final resp = await _client
        .from('profiles')
        .update(updates)
        .eq('id', user.id)
        .select()
        .single();
    return UserProfile.fromJson(resp);
  }

  Future<List<Map<String, dynamic>>> getCallHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    // Step 1: fetch call rows
    final calls = await _client
        .from('call_history')
        .select('*')
        .or('user_a.eq.${user.id},user_b.eq.${user.id}')
        .order('started_at', ascending: false)
        .limit(10);

    final callList = List<Map<String, dynamic>>.from(calls);
    if (callList.isEmpty) return callList;

    // Step 2: collect unique partner IDs (avoids Supabase FK join issues)
    final partnerIds = <String>{};
    for (final call in callList) {
      final pid = call['user_a'] == user.id ? call['user_b'] : call['user_a'];
      if (pid != null) partnerIds.add(pid as String);
    }

    // Step 3: batch fetch partner profiles
    final profileMap = <String, Map<String, dynamic>>{};
    if (partnerIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id,name,age,gender,avatar_url,bio')
          .inFilter('id', partnerIds.toList());
      for (final p in List<Map<String, dynamic>>.from(profiles)) {
        profileMap[p['id'] as String] = p;
      }
    }

    // Step 4: merge partner profile into each call row using new mutable maps
    // (Supabase returns immutable maps — direct assignment would silently fail)
    return callList.map((call) {
      final isUserA = call['user_a'] == user.id;
      final pid = isUserA ? call['user_b'] : call['user_a'];
      final profile = pid != null ? profileMap[pid as String] : null;
      return <String, dynamic>{
        ...call,
        if (isUserA) 'user_b_profile': profile else 'user_a_profile': profile,
      };
    }).toList();
  }
}
