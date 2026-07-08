import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../services/block_service.dart';
import '../../services/direct_call_service.dart';
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
  final _blockService = BlockService();
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
    final allFriends = await _friendService.getFriends();
    final blockedIds = await _blockService.getBlockedUserIds();
    final friends = allFriends
        .where((f) => !blockedIds.contains(_partnerId(f, myId)))
        .toList();
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

    // Sort by last message timestamp — most recent first
    if (mounted) {
      setState(() {
        _friends.sort((a, b) {
          final pidA = _partnerId(a, myId);
          final pidB = _partnerId(b, myId);
          final msgA = _lastMessages[pidA];
          final msgB = _lastMessages[pidB];
          if (msgA == null && msgB == null) return 0;
          if (msgA == null) return 1;
          if (msgB == null) return -1;
          final timeA = msgA['created_at'] as String? ?? '';
          final timeB = msgB['created_at'] as String? ?? '';
          return timeB.compareTo(timeA);
        });
      });
    }

    final ids = friends.map((f) => _partnerId(f, myId)).toList();
    _presenceSub?.cancel();
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

  Future<void> _callFriend(BuildContext ctx, String partnerId, String name, String? avatarUrl) async {
    final status = _presenceMap[partnerId] ?? 'offline';
    if (status == 'offline') {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('User is offline')),
      );
      return;
    }
    if (status == 'in_call') {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('User is currently in a call')),
      );
      return;
    }
    final data = await DirectCallService.instance.initiateCall(partnerId);
    if (!mounted || data == null) {
      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Could not start call. Try again.')),
      );
      return;
    }
    final event = MatchEvent(
      channelName: data['channel_name'] as String,
      agoraToken: data['agora_token'] as String,
      agoraUid: data['agora_uid'] as int,
      agoraAppId: data['agora_app_id'] as String,
      partnerId: partnerId,
      partner: PartnerInfo(name: name, avatarUrl: avatarUrl),
    );
    ctx.push('/call', extra: event);
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
          onPressed: () => context.pop(),
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
                        icon: Icon(
                          Icons.phone_outlined,
                          color: (_presenceMap[partnerId] ?? 'offline') == 'online'
                              ? kPrimary
                              : kTextMuted,
                        ),
                        tooltip: 'Call friend',
                        onPressed: () => _callFriend(context, partnerId, name, avatarUrl),
                      ),
                      onTap: () async {
                        await context.push('/chat/$partnerId');
                        if (mounted) _load();
                      },
                    );
                  },
                ),
    );
  }
}
