import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/friend_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendService = FriendService();
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await _friendService.getFriends();
      if (mounted) setState(() { _friends = f; _loading = false; });
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
          onPressed: () => context.pop(),
        ),
        title: Text(
          _loading ? 'Friends' : 'Friends (${_friends.length})',
          style: const TextStyle(color: kTextPrimary),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _friends.isEmpty
              ? const Center(
                  child: Text(
                    'No friends yet\nStart calling to connect!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _friends.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (_, i) {
                    final f = _friends[i];
                    final other = f['partner_profile'] as Map<String, dynamic>? ?? {};
                    final name = other['name'] as String? ?? 'Friend';
                    final avatar = other['avatar_url'] as String?;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: kPrimary,
                        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                        child: avatar == null
                            ? Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      title: Text(name, style: const TextStyle(color: kTextPrimary, fontSize: 15)),
                      trailing: const Icon(Icons.people, color: Colors.green, size: 18),
                    );
                  },
                ),
    );
  }
}
