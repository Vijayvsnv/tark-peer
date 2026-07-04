class PartnerInfo {
  final String name;
  final int? age;
  final String? gender;
  final String? avatarUrl;
  final String? bio;
  final String? occupation;
  final String? sector;
  final String? country;
  final String? state;
  final String? motherTongue;

  const PartnerInfo({
    required this.name,
    this.age,
    this.gender,
    this.avatarUrl,
    this.bio,
    this.occupation,
    this.sector,
    this.country,
    this.state,
    this.motherTongue,
  });

  factory PartnerInfo.fromJson(Map<String, dynamic> json) => PartnerInfo(
        name: json['name'] as String? ?? 'User',
        age: json['age'] as int?,
        gender: json['gender'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        occupation: json['occupation'] as String?,
        sector: json['sector'] as String?,
        country: json['country'] as String?,
        state: json['state'] as String?,
        motherTongue: json['mother_tongue'] as String?,
      );
}

class MatchEvent {
  final String channelName;
  final String agoraToken;
  final int agoraUid;
  final String agoraAppId;
  final String partnerId;
  final PartnerInfo partner;

  const MatchEvent({
    required this.channelName,
    required this.agoraToken,
    required this.agoraUid,
    required this.agoraAppId,
    required this.partnerId,
    required this.partner,
  });

  factory MatchEvent.fromJson(Map<String, dynamic> json) => MatchEvent(
        channelName: json['channel_name'] as String,
        agoraToken: json['agora_token'] as String,
        agoraUid: json['agora_uid'] as int,
        agoraAppId: json['agora_app_id'] as String,
        partnerId: json['partner_id'] as String? ?? '',
        partner: PartnerInfo.fromJson(json['partner'] as Map<String, dynamic>),
      );
}
