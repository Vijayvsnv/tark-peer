class UserProfile {
  final String id;
  final String name;
  final int? age;
  final String? gender;
  final String? bio;
  final String? avatarUrl;
  final bool isPremium;
  final int totalCalls;

  const UserProfile({
    required this.id,
    required this.name,
    this.age,
    this.gender,
    this.bio,
    this.avatarUrl,
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
        'is_premium': isPremium,
        'total_calls': totalCalls,
      };

  bool get isProfileComplete => age != null && gender != null;
}
