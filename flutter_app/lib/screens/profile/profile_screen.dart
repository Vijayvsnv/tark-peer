import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _auth = AuthService();
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _profileService.getMyProfile();
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
          onPressed: () => context.go('/home'),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  UserAvatar(
                    name: _profile?.name ?? 'U',
                    imageUrl: _profile?.avatarUrl,
                    radius: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile?.name ?? 'User',
                    style: const TextStyle(
                      color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (_profile?.bio != null && _profile!.bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _profile!.bio!,
                      style: const TextStyle(color: kTextSecondary, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (_profile?.age != null || _profile?.gender != null)
                    Text(
                      [
                        if (_profile?.age != null) '${_profile!.age} yrs',
                        if (_profile?.gender != null) _profile!.gender!,
                      ].join(' • '),
                      style: const TextStyle(color: kTextSecondary, fontSize: 13),
                    ),
                  if (_profile?.state != null || _profile?.country != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: kTextSecondary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          [
                            if (_profile?.state != null) _profile!.state!,
                            if (_profile?.country != null) _profile!.country!,
                          ].join(', '),
                          style: const TextStyle(color: kTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                  if ((_profile?.occupation != null && _profile!.occupation!.trim().isNotEmpty)
                      || _profile?.sector != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        [
                          if (_profile?.occupation != null && _profile!.occupation!.trim().isNotEmpty)
                            _profile!.occupation!,
                          if (_profile?.sector != null) _profile!.sector!,
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                  if (_profile?.motherTongue != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.translate_outlined,
                            color: kTextSecondary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _profile!.motherTongue!,
                          style: const TextStyle(color: kTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/setup'),
                    icon: const Icon(Icons.edit, size: 16, color: kPrimary),
                    label: const Text('Edit Profile', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kPrimary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _navCard(
                        context,
                        icon: Icons.people_alt_outlined,
                        label: 'Friends',
                        onTap: () => context.push('/friends'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _navCard(
                        context,
                        icon: Icons.call_outlined,
                        label: 'Calls',
                        onTap: () => context.push('/calls'),
                      )),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _auth.signOut();
                        if (mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout, color: kDanger),
                      label: const Text('Logout', style: TextStyle(color: kDanger, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kDanger, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _navCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: kPrimaryDeep.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
