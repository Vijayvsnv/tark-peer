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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Avatar with pencil badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        name: _profile?.name ?? 'U',
                        imageUrl: _profile?.avatarUrl,
                        radius: 48,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => context.push('/setup'),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: kPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Name only
                  Text(
                    _profile?.name ?? 'User',
                    style: const TextStyle(
                      color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  // Friends / Calls / Rooms — vertical list
                  _navCard(
                    context,
                    icon: Icons.people_alt_outlined,
                    label: 'Friends',
                    onTap: () => context.push('/friends'),
                  ),
                  const SizedBox(height: 10),
                  _navCard(
                    context,
                    icon: Icons.call_outlined,
                    label: 'Calls',
                    onTap: () => context.push('/calls'),
                  ),
                  const SizedBox(height: 10),
                  _navCard(
                    context,
                    icon: Icons.meeting_room_outlined,
                    label: 'Rooms',
                    onTap: () => context.push('/rooms'),
                  ),
                  const SizedBox(height: 28),
                  _navCard(
                    context,
                    icon: Icons.logout,
                    label: 'Logout',
                    onTap: _confirmLogout,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout?',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'You will be signed out of Tark Peer.',
          style: TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _auth.signOut();
      if (mounted) context.go('/login');
    }
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
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimary, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, color: kPrimary, size: 22),
          ],
        ),
      ),
    );
  }
}

