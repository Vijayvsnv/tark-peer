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

  Future<Map<String, dynamic>> getCallStats() async {
    final user = _client.auth.currentUser;
    if (user == null) return _emptyStats();

    final raw = await _client
        .from('call_history')
        .select('started_at, duration_seconds')
        .or('user_a.eq.${user.id},user_b.eq.${user.id}')
        .order('started_at', ascending: false);

    final calls = List<Map<String, dynamic>>.from(raw);
    if (calls.isEmpty) return _emptyStats();

    // ── Basic totals ──────────────────────────────────────────────────────────
    final totalCalls = calls.length;
    final totalSeconds = calls.fold<int>(
      0, (sum, c) => sum + ((c['duration_seconds'] as int?) ?? 0));
    final longestSeconds = calls.fold<int>(
      0, (mx, c) { final d = (c['duration_seconds'] as int?) ?? 0; return d > mx ? d : mx; });

    // ── Streak (consecutive days with at least one call) ──────────────────────
    final callDates = calls
        .map((c) {
          final iso = c['started_at'] as String?;
          if (iso == null) return null;
          final dt = DateTime.parse(iso).toLocal();
          return DateTime(dt.year, dt.month, dt.day);
        })
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    int streak = 0;
    if (callDates.isNotEmpty) {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final yesterday = todayDate.subtract(const Duration(days: 1));
      if (callDates.first == todayDate || callDates.first == yesterday) {
        DateTime expected = callDates.first;
        for (final d in callDates) {
          if (d == expected) {
            streak++;
            expected = expected.subtract(const Duration(days: 1));
          } else {
            break;
          }
        }
      }
    }

    // ── This week vs last week ────────────────────────────────────────────────
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));

    int thisWeek = 0, lastWeek = 0;
    for (final c in calls) {
      final iso = c['started_at'] as String?;
      if (iso == null) continue;
      final dt = DateTime.parse(iso).toLocal();
      final d = DateTime(dt.year, dt.month, dt.day);
      if (!d.isBefore(thisWeekStart)) {
        thisWeek++;
      } else if (!d.isBefore(lastWeekStart) && !d.isAfter(lastWeekEnd)) {
        lastWeek++;
      }
    }

    return {
      'total_calls': totalCalls,
      'total_seconds': totalSeconds,
      'longest_seconds': longestSeconds,
      'streak': streak,
      'this_week': thisWeek,
      'last_week': lastWeek,
    };
  }

  Map<String, dynamic> _emptyStats() => {
    'total_calls': 0,
    'total_seconds': 0,
    'longest_seconds': 0,
    'streak': 0,
    'this_week': 0,
    'last_week': 0,
  };
}
