import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../services/message_service.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String friendId;
  const ChatScreen({super.key, required this.friendId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageService = MessageService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  String _friendName = '';
  String? _friendAvatarUrl;
  bool _sending = false;
  RealtimeChannel? _channel;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadFriend();
    _loadMessages();
    _channel = _messageService.subscribeToMessages(widget.friendId, _loadMessages);
    _messageService.markRead(widget.friendId);
  }

  Future<void> _loadFriend() async {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', widget.friendId)
        .single();
    if (mounted) {
      setState(() {
        _friendName = profile['name'] ?? 'Unknown';
        _friendAvatarUrl = profile['avatar_url'];
      });
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _messageService.fetchMessages(widget.friendId);
    if (mounted) {
      setState(() => _messages = msgs);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await _messageService.sendMessage(widget.friendId, text);
      await _loadMessages();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _expiryLabel(String expiresAt) {
    final left = DateTime.parse(expiresAt).difference(DateTime.now());
    if (left.isNegative) return 'expiring';
    if (left.inHours >= 1) return 'deletes in ${left.inHours}h';
    if (left.inMinutes >= 1) return 'deletes in ${left.inMinutes}m';
    return 'deletes soon';
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chat'),
        ),
        title: Row(
          children: [
            UserAvatar(name: _friendName.isEmpty ? '?' : _friendName, imageUrl: _friendAvatarUrl, radius: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _friendName.isEmpty ? '...' : _friendName,
                style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: kPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Direct call coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 24h notice banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: kSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 13, color: kTextMuted),
                const SizedBox(width: 4),
                Text(
                  'Messages delete after 24 hours',
                  style: TextStyle(color: kTextMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.waving_hand_outlined, size: 48, color: kTextMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'No messages yet\nSay hello!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextSecondary, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final msg = _messages[i];
                      final isMe = msg['sender_id'] == _myId;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: isMe ? kPrimary : kSurface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                msg['content'] as String,
                                style: TextStyle(
                                  color: isMe ? Colors.white : kTextPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _expiryLabel(msg['expires_at'] as String),
                                style: TextStyle(
                                  color: isMe ? Colors.white54 : kTextMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: kBackground,
              border: Border(top: BorderSide(color: kBorder, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: kTextPrimary),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
