import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../services/friend_service.dart';
import '../../services/message_service.dart';
import '../../services/presence_service.dart';
import '../../widgets/user_avatar.dart';

String _partnerId(Map<String, dynamic> f, String myId) {
  final req = f['requester_id'] as String;
  return req == myId ? f['receiver_id'] as String : req;
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _friendService = FriendService();
  final _messageService = MessageService();
  final _presenceService = PresenceService();

  List<Map<String, dynamic>> _friends = [];
  Map<String, Map<String, dynamic>?> _lastMessages = {};
  Map<String, String> _presenceMap = {};
  StreamSubscription? _presenceSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myId = Supabase.instance.client.auth.currentUser!.id;
    final friends = await _friendService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _loading = false;
    });

    for (final f in friends) {
      final pid = _partnerId(f, myId);
      final msg = await _messageService.getLastMessage(pid);
      if (mounted) setState(() => _lastMessages[pid] = msg);
    }

    final ids = friends.map((f) => _partnerId(f, myId)).toList();
    _presenceSub = _presenceService.watchPresence(ids).listen((map) {
      if (mounted) setState(() => _presenceMap = map);
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _presenceService.dispose();
    super.dispose();
  }

  Color _dotColor(String partnerId) {
    final status = _presenceMap[partnerId] ?? 'offline';
    if (status == 'online') return kSuccess;
    if (status == 'in_call') return kDanger;
    return kTextMuted;
  }

  String _subtitle(String partnerId, String friendName) {
    final msg = _lastMessages[partnerId];
    if (msg == null) return 'Tap to start messaging';
    final myId = Supabase.instance.client.auth.currentUser!.id;
    final isMe = msg['sender_id'] == myId;
    final preview = msg['content'] as String? ?? '';
    final text = '${isMe ? "You" : friendName}: $preview';
    return text.length > 42 ? '${text.substring(0, 42)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Messages'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: kTextMuted),
                      const SizedBox(height: 16),
                      const Text(
                        'No friends yet',
                        style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add friends to start chatting!',
                        style: TextStyle(color: kTextSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _friends.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) {
                    final friend = _friends[i];
                    final myId = Supabase.instance.client.auth.currentUser!.id;
                    final partnerId = _partnerId(friend, myId);
                    final profile = friend['partner_profile'] as Map<String, dynamic>?;
                    final name = profile?['name'] as String? ?? 'Unknown';
                    final avatarUrl = profile?['avatar_url'] as String?;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(name: name, imageUrl: avatarUrl, radius: 26),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _dotColor(partnerId),
                                shape: BoxShape.circle,
                                border: Border.all(color: kBackground, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: kTextPrimary),
                      ),
                      subtitle: Text(
                        _subtitle(partnerId, name),
                        style: const TextStyle(color: kTextSecondary, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.phone_outlined, color: kPrimary),
                        tooltip: 'Call friend',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Direct call coming soon!')),
                          );
                        },
                      ),
                      onTap: () => context.go('/chat/$partnerId'),
                    );
                  },
                ),
    );
  }
}
