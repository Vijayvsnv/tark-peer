import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/room_models.dart';
import '../../services/call_audio_manager.dart';
import '../../services/call_service.dart';
import '../../services/room_service.dart';
import '../../widgets/user_avatar.dart';

class RoomLobbyScreen extends StatefulWidget {
  final RoomInfo room;
  const RoomLobbyScreen({super.key, required this.room});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen>
    with TickerProviderStateMixin {
  final _callService = CallService();
  final _audioManager = CallAudioManager();
  final _roomService = RoomService();

  // slot index 0 = slot 1, null = empty
  late List<RoomMember?> _slots;
  // agora uid → slot number (uid=0 means local user)
  Map<int, int> _uidToSlot = {};
  // slot numbers currently speaking
  Set<int> _speakingSlots = {};

  bool _micEnabled = true;
  bool _speakerEnabled = false;
  bool _isLeaving = false;

  RealtimeChannel? _memberChannel;
  RealtimeChannel? _roomChannel;

  // Single shared glow animation — applied conditionally per box
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _initSlots();
    _subscribeRealtime();
    _startCall();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _memberChannel?.unsubscribe();
    _roomChannel?.unsubscribe();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  void _initSlots() {
    final slots = List<RoomMember?>.filled(widget.room.maxMembers, null);
    final uidToSlot = <int, int>{};
    uidToSlot[0] = widget.room.mySlot; // 0 = local user in Agora

    for (final m in widget.room.members) {
      if (m.slotNumber >= 1 && m.slotNumber <= widget.room.maxMembers) {
        slots[m.slotNumber - 1] = m;
      }
      if (m.agoraUid != null) {
        uidToSlot[m.agoraUid!] = m.slotNumber;
      }
    }
    _slots = slots;
    _uidToSlot = uidToSlot;
  }

  // ── Agora call ────────────────────────────────────────────────────────────

  Future<void> _startCall() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required'),
            backgroundColor: Colors.red,
          ),
        );
        context.go('/home');
      }
      return;
    }

    await _callService.joinCall(
      appId: widget.room.agoraAppId,
      channelName: 'room_${widget.room.code}',
      token: widget.room.agoraToken,
      uid: widget.room.agoraUid,
      onUserJoined: (_) => _fetchMembers(),
      onUserOffline: (_) => _fetchMembers(),
      onVolumesChanged: (vols) {
        if (!mounted) return;
        final speaking = <int>{};
        vols.forEach((uid, vol) {
          if (vol > 25 && _uidToSlot.containsKey(uid)) {
            speaking.add(_uidToSlot[uid]!);
          }
        });
        if (speaking != _speakingSlots) {
          setState(() => _speakingSlots = speaking);
        }
      },
    );

    await _audioManager.start();
    _audioManager.onMuteChanged = (muted) {
      if (mounted) _callService.setMicMuted(muted);
    };
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    final supabase = Supabase.instance.client;

    _memberChannel = supabase
        .channel('lobby_members_${widget.room.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.roomId,
          ),
          callback: (_) => _fetchMembers(),
        )
        .subscribe();

    _roomChannel = supabase
        .channel('room:${widget.room.roomId}')
        .onBroadcast(event: 'room_ended', callback: (_) => _onRoomEnded())
        .onBroadcast(event: 'member_left', callback: (_) => _fetchMembers())
        .subscribe();
  }

  Future<void> _fetchMembers() async {
    try {
      final members = await _roomService.getRoomMembers(widget.room.roomId);
      if (!mounted) return;

      final slots = List<RoomMember?>.filled(widget.room.maxMembers, null);
      final uidToSlot = <int, int>{};
      uidToSlot[0] = widget.room.mySlot;

      for (final m in members) {
        if (m.slotNumber >= 1 && m.slotNumber <= widget.room.maxMembers) {
          slots[m.slotNumber - 1] = m;
        }
        if (m.agoraUid != null) uidToSlot[m.agoraUid!] = m.slotNumber;
      }

      setState(() {
        _slots = slots;
        _uidToSlot = uidToSlot;
      });
    } catch (_) {}
  }

  // ── Leave ─────────────────────────────────────────────────────────────────

  void _onRoomEnded() {
    if (!mounted) return;
    _cleanup(navigate: false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room has ended'), backgroundColor: Colors.orange),
    );
    context.go('/home');
  }

  Future<void> _cleanup({bool navigate = true}) async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    try {
      _memberChannel?.unsubscribe();
      _roomChannel?.unsubscribe();
      _memberChannel = null;
      _roomChannel = null;
      await _audioManager.stop();
      await _callService.leaveCall();
      await _roomService.leaveRoom(widget.room.roomId);
    } catch (_) {}
    if (navigate && mounted) context.go('/home');
  }

  Future<bool> _confirmLeave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Room?', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
        content: const Text('You will leave the room. Others can continue talking.', style: TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) async {
        if (await _confirmLeave()) _cleanup();
      },
      child: Scaffold(
        backgroundColor: kCallBgTop,
        appBar: AppBar(
          backgroundColor: kCallBgTop,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () async {
              if (await _confirmLeave()) _cleanup();
            },
          ),
          title: Column(
            children: [
              Text(
                widget.room.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: _copyCode,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.room.code,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 3,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy_rounded, size: 12, color: Colors.white38),
                  ],
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_slots.where((s) => s != null).length}/${widget.room.maxMembers}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Member grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (_, __) => GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    children: List.generate(
                      widget.room.maxMembers,
                      (i) {
                        final member = i < _slots.length ? _slots[i] : null;
                        final slotNum = i + 1;
                        final isSpeaking = _speakingSlots.contains(slotNum);
                        final isMe = slotNum == widget.room.mySlot;
                        return _MemberBox(
                          slotNumber: slotNum,
                          member: member,
                          isSpeaking: isSpeaking,
                          glowValue: _glowAnim.value,
                          isMe: isMe,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Controls bar
            Container(
              decoration: BoxDecoration(
                color: kCallBgBottom,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                children: [
                  // Mic + Speaker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CtrlBtn(
                        icon: _micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                        label: _micEnabled ? 'Mute' : 'Unmute',
                        active: _micEnabled,
                        onTap: () {
                          _callService.toggleMic();
                          setState(() => _micEnabled = !_micEnabled);
                        },
                      ),
                      const SizedBox(width: 24),
                      _CtrlBtn(
                        icon: _speakerEnabled ? Icons.volume_up_rounded : Icons.hearing_rounded,
                        label: _speakerEnabled ? 'Speaker' : 'Earpiece',
                        active: _speakerEnabled,
                        activeColor: kPrimary,
                        onTap: () {
                          _callService.setSpeakerphone(!_speakerEnabled);
                          setState(() => _speakerEnabled = !_speakerEnabled);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Leave button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLeaving ? null : () async {
                        if (await _confirmLeave()) _cleanup();
                      },
                      icon: const Icon(Icons.call_end_rounded, size: 20),
                      label: const Text(
                        'Leave Room',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDanger,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: kDanger.withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.room.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room code copied!'),
        duration: Duration(seconds: 1),
        backgroundColor: kSuccess,
      ),
    );
  }
}

// ── Member Box ────────────────────────────────────────────────────────────────

class _MemberBox extends StatelessWidget {
  final int slotNumber;
  final RoomMember? member;
  final bool isSpeaking;
  final double glowValue;
  final bool isMe;

  const _MemberBox({
    required this.slotNumber,
    required this.member,
    required this.isSpeaking,
    required this.glowValue,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    if (member == null) return const _EmptySlot();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF162040),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSpeaking
              ? kAccent.withOpacity(0.3 + glowValue * 0.7)
              : Colors.white.withOpacity(0.07),
          width: isSpeaking ? 2 : 1,
        ),
        boxShadow: isSpeaking
            ? [BoxShadow(color: kAccent.withOpacity(0.25 * glowValue), blurRadius: 16, spreadRadius: 2)]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              // Avatar with speaking ring
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: isSpeaking ? const EdgeInsets.all(3) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isSpeaking
                      ? Border.all(color: kAccent.withOpacity(0.6 + glowValue * 0.4), width: 2)
                      : null,
                ),
                child: UserAvatar(
                  name: member!.name ?? 'U',
                  imageUrl: member!.avatarUrl,
                  radius: 28,
                ),
              ),
              // "You" badge
              if (isMe)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded, size: 10, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              isMe ? 'You' : (member!.name ?? 'User'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          if (member!.country != null) ...[
            const SizedBox(height: 3),
            Text(
              member!.country!,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
          if (isSpeaking) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => _Dot(index: i, glowValue: glowValue)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final int index;
  final double glowValue;
  const _Dot({required this.index, required this.glowValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 5,
      height: 5 + (index == 1 ? glowValue * 4 : (1 - glowValue) * 3),
      decoration: BoxDecoration(color: kAccent.withOpacity(0.7), borderRadius: BorderRadius.circular(3)),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_outlined, size: 32, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 10),
          Text(
            'Waiting...',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Control Button ────────────────────────────────────────────────────────────

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.label,
    required this.active,
    this.activeColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active ? activeColor.withOpacity(0.15) : Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? activeColor.withOpacity(0.4) : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(icon, color: active ? activeColor : Colors.white54, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
