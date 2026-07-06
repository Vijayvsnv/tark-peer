class RoomMember {
  final String? memberId;
  final String userId;
  final String? name;
  final String? avatarUrl;
  final String? country;
  final int slotNumber;
  final int? agoraUid;

  const RoomMember({
    this.memberId,
    required this.userId,
    this.name,
    this.avatarUrl,
    this.country,
    required this.slotNumber,
    this.agoraUid,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return RoomMember(
      memberId: json['id'] as String?,
      userId: json['user_id'] as String,
      name: (profile?['name'] ?? json['name']) as String?,
      avatarUrl: (profile?['avatar_url'] ?? json['avatar_url']) as String?,
      country: (profile?['country'] ?? json['country']) as String?,
      slotNumber: json['slot_number'] as int,
      agoraUid: json['agora_uid'] as int?,
    );
  }
}

class RoomInfo {
  final String roomId;
  final String code;
  final String name;
  final String type;
  final int maxMembers;
  final int mySlot;
  final String agoraToken;
  final int agoraUid;
  final String agoraAppId;
  final List<RoomMember> members;

  const RoomInfo({
    required this.roomId,
    required this.code,
    required this.name,
    required this.type,
    required this.maxMembers,
    required this.mySlot,
    required this.agoraToken,
    required this.agoraUid,
    required this.agoraAppId,
    required this.members,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? [];
    return RoomInfo(
      roomId: json['room_id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      maxMembers: json['max_members'] as int,
      mySlot: json['my_slot'] as int,
      agoraToken: json['agora_token'] as String,
      agoraUid: json['agora_uid'] as int,
      agoraAppId: json['agora_app_id'] as String,
      members: rawMembers
          .map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PublicRoom {
  final String roomId;
  final String code;
  final String name;
  final int maxMembers;
  final int memberCount;

  const PublicRoom({
    required this.roomId,
    required this.code,
    required this.name,
    required this.maxMembers,
    required this.memberCount,
  });

  factory PublicRoom.fromJson(Map<String, dynamic> json) {
    return PublicRoom(
      roomId: (json['room_id'] ?? json['id']) as String,
      code: json['code'] as String,
      name: json['name'] as String,
      maxMembers: json['max_members'] as int,
      memberCount: json['member_count'] as int,
    );
  }
}
