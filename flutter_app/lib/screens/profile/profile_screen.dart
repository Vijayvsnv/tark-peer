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
          icon: const Icon(Icons.arrow_back, color: kTextSecondary),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Profile', style: TextStyle(color: kTextPrimary)),
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
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/setup'),
                    icon: const Icon(Icons.edit, size: 16, color: kPrimary),
                    label: const Text('Edit Profile', style: TextStyle(color: kPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('Logout', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPrimary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kPrimary, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
