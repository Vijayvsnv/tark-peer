class UserProfile {
  final String id;
  final String name;
  final int? age;
  final String? gender;
  final String? bio;
  final String? avatarUrl;
  final String? occupation;
  final String? sector;
  final String? country;
  final String? state;
  final String? motherTongue;
  final double avgRating;
  final int ratingCount;
  final bool isPremium;
  final int totalCalls;

  const UserProfile({
    required this.id,
    required this.name,
    this.age,
    this.gender,
    this.bio,
    this.avatarUrl,
    this.occupation,
    this.sector,
    this.country,
    this.state,
    this.motherTongue,
    this.avgRating = 0,
    this.ratingCount = 0,
    this.isPremium = false,
    this.totalCalls = 0,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        age: json['age'] as int?,
        gender: json['gender'] as String?,
        bio: json['bio'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        occupation: json['occupation'] as String?,
        sector: json['sector'] as String?,
        country: json['country'] as String?,
        state: json['state'] as String?,
        motherTongue: json['mother_tongue'] as String?,
        avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['rating_count'] as int?) ?? 0,
        isPremium: (json['is_premium'] as bool?) ?? false,
        totalCalls: (json['total_calls'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (occupation != null) 'occupation': occupation,
        if (sector != null) 'sector': sector,
        if (country != null) 'country': country,
        if (state != null) 'state': state,
        if (motherTongue != null) 'mother_tongue': motherTongue,
        'is_premium': isPremium,
        'total_calls': totalCalls,
      };

  bool get isProfileComplete =>
      age != null && gender != null && country != null && state != null;
}
