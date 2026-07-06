import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/room_models.dart';
import '../../services/room_service.dart';

class PublicRoomsScreen extends StatefulWidget {
  const PublicRoomsScreen({super.key});

  @override
  State<PublicRoomsScreen> createState() => _PublicRoomsScreenState();
}

class _PublicRoomsScreenState extends State<PublicRoomsScreen> {
  final _roomService = RoomService();
  List<PublicRoom> _rooms = [];
  bool _loading = true;
  String? _joiningCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rooms = await _roomService.getPublicRooms();
    if (mounted) setState(() { _rooms = rooms; _loading = false; });
  }

  Future<void> _join(PublicRoom room) async {
    setState(() => _joiningCode = room.code);
    try {
      final roomInfo = await _roomService.joinRoom(room.code);
      if (mounted) context.pushReplacement('/rooms/lobby', extra: roomInfo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Public Rooms',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kTextSecondary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _rooms.isEmpty
              ? _EmptyState(onRefresh: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: kPrimary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _PublicRoomCard(
                      room: _rooms[i],
                      isJoining: _joiningCode == _rooms[i].code,
                      onJoin: () => _join(_rooms[i]),
                    ),
                  ),
                ),
    );
  }
}

class _PublicRoomCard extends StatelessWidget {
  final PublicRoom room;
  final bool isJoining;
  final VoidCallback onJoin;

  const _PublicRoomCard({required this.room, required this.isJoining, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final isFull = room.memberCount >= room.maxMembers;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(color: kPrimaryDeep.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.public_rounded, color: kAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 13, color: kTextMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${room.memberCount}/${room.maxMembers} members',
                      style: const TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isFull ? kDanger.withOpacity(0.1) : kSuccess.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isFull ? 'Full' : 'Open',
                        style: TextStyle(
                          color: isFull ? kDanger : kSuccess,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isFull)
            SizedBox(
              width: 72,
              height: 36,
              child: ElevatedButton(
                onPressed: isJoining ? null : onJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: isJoining
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Join', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.meeting_room_outlined, size: 64, color: kTextMuted.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No public rooms right now', style: TextStyle(color: kTextSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Be the first to create one!', style: TextStyle(color: kTextMuted, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
