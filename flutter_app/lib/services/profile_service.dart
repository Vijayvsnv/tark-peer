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
    final resp = await _client
        .from('call_history')
        .select()
        .or('user_a.eq.${user.id},user_b.eq.${user.id}')
        .order('started_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(resp);
  }
}
