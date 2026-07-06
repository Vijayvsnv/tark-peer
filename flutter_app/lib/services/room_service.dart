import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/room_models.dart';
import 'auth_service.dart';

class RoomService {
  final _client = Supabase.instance.client;
  final _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.accessToken ?? ""}',
      };

  Future<RoomInfo> createRoom({
    required String name,
    required String type,
    required int maxMembers,
  }) async {
    final resp = await http.post(
      Uri.parse('$kBackendUrl/room/create'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'type': type,
        'max_members': maxMembers,
      }),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['detail'] as String? ?? 'Failed to create room');
    }
    return RoomInfo.fromJson(body);
  }

  Future<RoomInfo> joinRoom(String code) async {
    final resp = await http.post(
      Uri.parse('$kBackendUrl/room/join'),
      headers: _headers,
      body: jsonEncode({'code': code.toUpperCase()}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['detail'] as String? ?? 'Failed to join room');
    }
    return RoomInfo.fromJson(body);
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      await http.post(
        Uri.parse('$kBackendUrl/room/leave'),
        headers: _headers,
        body: jsonEncode({'room_id': roomId}),
      );
    } catch (_) {
      // Best-effort — silently ignore errors
    }
  }

  Future<List<PublicRoom>> getPublicRooms() async {
    try {
      final resp = await http.get(
        Uri.parse('$kBackendUrl/room/public'),
        headers: _headers,
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => PublicRoom.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RoomMember>> getRoomMembers(String roomId) async {
    // Step 1: fetch active room_members ordered by slot
    final rawMembers = await _client
        .from('room_members')
        .select('*')
        .eq('room_id', roomId)
        .eq('is_active', true)
        .order('slot_number');

    final memberList = List<Map<String, dynamic>>.from(rawMembers);
    if (memberList.isEmpty) return [];

    // Step 2: collect unique user_ids
    final userIds = memberList
        .map((m) => m['user_id'] as String)
        .toSet()
        .toList();

    // Step 3: batch fetch profiles
    final profileMap = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id,name,avatar_url,country')
          .inFilter('id', userIds);
      for (final p in List<Map<String, dynamic>>.from(profiles)) {
        profileMap[p['id'] as String] = p;
      }
    }

    // Step 4: merge using spread operator (Supabase returns immutable maps)
    return memberList.map((member) {
      final profile = profileMap[member['user_id'] as String];
      final merged = <String, dynamic>{
        ...member,
        if (profile != null) 'profile': profile,
      };
      return RoomMember.fromJson(merged);
    }).toList();
  }
}
