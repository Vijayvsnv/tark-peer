import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../widgets/user_avatar.dart';

class FriendProfileScreen extends StatefulWidget {
  final String userId;

  const FriendProfileScreen({super.key, required this.userId});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final _profileService = ProfileService();
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _profileService.getProfileById(widget.userId);
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _profile == null
              ? const Center(
                  child: Text(
                    'Profile not found',
                    style: TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),
                      UserAvatar(
                        name: _profile!.name,
                        imageUrl: _profile!.avatarUrl,
                        radius: 52,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _profile!.name,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_profile!.ratingCount > 0) ...[
                        const SizedBox(height: 6),
                        _RatingChip(avg: _profile!.avgRating, count: _profile!.ratingCount),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: kSuccess.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people, color: kSuccess, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Friend',
                              style: TextStyle(
                                color: kSuccess,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_profile!.bio != null && _profile!.bio!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _profile!.bio!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kTextSecondary, fontSize: 14),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _detailsCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _detailsCard() {
    final rows = <_DetailRow>[
      if (_profile!.age != null)
        _DetailRow(icon: Icons.cake_outlined, label: 'Age', value: '${_profile!.age}'),
      if (_profile!.gender != null)
        _DetailRow(
          icon: Icons.people_outline,
          label: 'Gender',
          value: _profile!.gender![0].toUpperCase() + _profile!.gender!.substring(1),
        ),
      if (_profile!.country != null || _profile!.state != null)
        _DetailRow(
          icon: Icons.location_on_outlined,
          label: 'From',
          value: [
            if (_profile!.state != null) _profile!.state!,
            if (_profile!.country != null) _profile!.country!,
          ].join(', '),
        ),
      if (_profile!.motherTongue != null)
        _DetailRow(
          icon: Icons.translate_outlined,
          label: 'Mother Tongue',
          value: _profile!.motherTongue!,
        ),
      if (_profile!.occupation != null && _profile!.occupation!.trim().isNotEmpty)
        _DetailRow(
          icon: Icons.work_outline,
          label: 'Occupation',
          value: _profile!.occupation!,
        ),
      if (_profile!.sector != null)
        _DetailRow(
          icon: Icons.business_center_outlined,
          label: 'Sector',
          value: _profile!.sector!,
        ),
    ];

    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Text(
          'No additional details shared',
          style: TextStyle(color: kTextSecondary, fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(height: 1, color: kBorder, indent: 52, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final double avg;
  final int count;

  const _RatingChip({required this.avg, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC933).withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFEAB308), size: 16),
          const SizedBox(width: 4),
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              color: Color(0xFF8B6D0B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPrimary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
