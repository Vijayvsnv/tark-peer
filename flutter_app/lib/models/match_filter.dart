class MatchFilter {
  final String? gender;   // 'male' | 'female' | null = any
  final String? ageRange; // '18-22' | '22-30' | '30-40' | '40+' | null = any
  final double? minRating;
  final double? maxRating;

  const MatchFilter({
    this.gender,
    this.ageRange,
    this.minRating,
    this.maxRating,
  });

  bool get hasAnyFilter =>
      gender != null || ageRange != null || minRating != null || maxRating != null;

  Map<String, dynamic> toQuery() => {
        if (gender != null) 'gender': gender,
        if (ageRange != null) 'age_range': ageRange,
        if (minRating != null) 'min_rating': minRating.toString(),
        if (maxRating != null) 'max_rating': maxRating.toString(),
      };
}
