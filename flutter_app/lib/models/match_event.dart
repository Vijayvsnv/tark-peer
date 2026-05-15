class PartnerInfo {
  final String name;
  final int? age;
  final String? gender;
  final String? avatarUrl;

  const PartnerInfo({
    required this.name,
    this.age,
    this.gender,
    this.avatarUrl,
  });

  factory PartnerInfo.fromJson(Map<String, dynamic> json) => PartnerInfo(
        name: json['name'] as String,
        age: json['age'] as int?,
        gender: json['gender'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class MatchEvent {
  final String channelName;
  final String agoraToken;
  final int agoraUid;
  final String agoraAppId;
  final PartnerInfo partner;

  const MatchEvent({
    required this.channelName,
    required this.agoraToken,
    required this.agoraUid,
    required this.agoraAppId,
    required this.partner,
  });

  factory MatchEvent.fromJson(Map<String, dynamic> json) => MatchEvent(
        channelName: json['channel_name'] as String,
        agoraToken: json['agora_token'] as String,
        agoraUid: json['agora_uid'] as int,
        agoraAppId: json['agora_app_id'] as String,
        partner: PartnerInfo.fromJson(json['partner'] as Map<String, dynamic>),
      );
}
