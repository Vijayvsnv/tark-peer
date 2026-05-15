import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/friend_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _friendService = FriendService();
  final _auth = AuthService();
  UserProfile? _profile;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _calls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        _profileService.getMyProfile(),
        _friendService.getFriends(),
        _profileService.getCallHistory(),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as UserProfile?;
          _friends = results[1] as List<Map<String, dynamic>>;
          _calls = (results[2] as List<Map<String, dynamic>>).take(10).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getPartnerName(Map<String, dynamic> call) {
    final myId = _auth.currentUser?.id ?? '';
    if (call['user_a'] == myId) {
      return call['user_b_profile']?['name'] as String? ?? 'Unknown';
    }
    return call['user_a_profile']?['name'] as String? ?? 'Unknown';
  }

  String? _getPartnerId(Map<String, dynamic> call) {
    final myId = _auth.currentUser?.id ?? '';
    if (call['user_a'] == myId) return call['user_b'] as String?;
    return call['user_a'] as String?;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '—';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
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
                    style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (_profile?.bio != null && _profile!.bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_profile!.bio!, style: const TextStyle(color: kTextSecondary, fontSize: 14)),
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
                  const SizedBox(height: 28),
                  _sectionHeader('Friends (${_friends.length})'),
                  const SizedBox(height: 10),
                  _friends.isEmpty
                      ? _emptyState('No friends yet — start calling!')
                      : SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _friends.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 16),
                            itemBuilder: (_, i) {
                              final f = _friends[i];
                              final myId = _auth.currentUser?.id ?? '';
                              final other = (f['requester_id'] == myId ? f['receiver'] : f['requester']) as Map<String, dynamic>? ?? {};
                              final name = other['name'] as String? ?? 'Friend';
                              final avatar = other['avatar_url'] as String?;
                              return Column(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: kPrimary,
                                    backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                    child: avatar == null
                                        ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18))
                                        : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(name.split(' ')[0], style: const TextStyle(color: kTextSecondary, fontSize: 11)),
                                ],
                              );
                            },
                          ),
                        ),
                  const SizedBox(height: 28),
                  _sectionHeader('Recent Calls (last 10)'),
                  const SizedBox(height: 10),
                  _calls.isEmpty
                      ? _emptyState('No calls yet')
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _calls.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (_, i) {
                            final call = _calls[i];
                            final name = _getPartnerName(call);
                            final partnerId = _getPartnerId(call);
                            final duration = _formatDuration(call['duration_seconds'] as int?);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: kPrimary.withOpacity(0.2),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: kPrimary)),
                              ),
                              title: Text(name, style: const TextStyle(color: kTextPrimary, fontSize: 14)),
                              subtitle: Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 12, color: kTextSecondary),
                                  const SizedBox(width: 4),
                                  Text(duration, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                                ],
                              ),
                              trailing: partnerId != null
                                  ? _AddFriendButton(
                                      partnerId: partnerId,
                                      friendService: _friendService,
                                    )
                                  : null,
                            );
                          },
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

  Widget _sectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _emptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(msg, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
    );
  }
}

class _AddFriendButton extends StatefulWidget {
  final String partnerId;
  final FriendService friendService;

  const _AddFriendButton({required this.partnerId, required this.friendService});

  @override
  State<_AddFriendButton> createState() => _AddFriendButtonState();
}

class _AddFriendButtonState extends State<_AddFriendButton> {
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final s = await widget.friendService.getFriendshipStatus(widget.partnerId);
    if (mounted) setState(() { _status = s; _loading = false; });
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await widget.friendService.sendRequest(widget.partnerId);
      if (mounted) setState(() { _status = 'pending'; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary));
    if (_status == 'accepted') return const Icon(Icons.people, color: Colors.green, size: 20);
    if (_status == 'pending') return const Text('Sent', style: TextStyle(color: kTextSecondary, fontSize: 12));
    return GestureDetector(
      onTap: _send,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: kPrimary)),
        child: const Text('+ Add', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
