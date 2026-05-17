import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../services/auth_service.dart';
import '../../services/call_audio_manager.dart';
import '../../services/call_service.dart';
import '../../services/friend_service.dart';
import '../../widgets/user_avatar.dart';

// Agora AudioRoute int constants
const int _kRouteHeadset = 0;
const int _kRouteEarpiece = 1;
const int _kRouteHeadsetNoMic = 2;
const int _kRouteBluetooth = 5;

class CallScreen extends StatefulWidget {
  final MatchEvent event;
  const CallScreen({super.key, required this.event});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final _callService = CallService();
  final _audioManager = CallAudioManager();
  final _friendService = FriendService();
  final _auth = AuthService();

  int _remaining = kCallDurationSeconds;
  Timer? _timer;
  RealtimeChannel? _roomChannel;

  bool _micEnabled = true;
  bool _speakerEnabled = false;
  bool _phoneCallActive = false; // true while a phone call is interrupting
  int _audioRoute = -1; // -1 = default/earpiece

  bool _joining = true;
  bool _partnerSpeaking = false;
  String? _friendStatus;
  bool _showWarning = false;

  // Pulse animation — plays when partner is speaking
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Fade animation — connecting screen
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fadeAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut),
    );

    _start();
  }

  Future<void> _start() async {
    // Mic permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone access chahiye voice call ke liye'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        context.go('/home');
      }
      return;
    }

    try {
      await _callService.joinCall(
        appId: widget.event.agoraAppId,
        channelName: widget.event.channelName,
        token: widget.event.agoraToken,
        uid: widget.event.agoraUid,
        onUserJoined: (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.person_add, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Partner joined!'),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onUserOffline: (_) => _endCall(reason: 'partner_left'),
        onPartnerSpeaking: (speaking) {
          if (mounted && speaking != _partnerSpeaking) {
            setState(() => _partnerSpeaking = speaking);
          }
        },
        onAudioRoutingChanged: (routing) {
          if (mounted) setState(() => _audioRoute = routing);
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call join failed: $e'), backgroundColor: Colors.red),
        );
        context.go('/home');
        return;
      }
    }

    // Subscribe to room:{channelName} via Supabase Realtime for call_ended events.
    // This works across backend instances — no WS needed here.
    _roomChannel = Supabase.instance.client
        .channel('room:${widget.event.channelName}')
      ..onBroadcast(
        event: 'call_ended',
        callback: (payload) {
          final reason = (payload['reason'] as String?) ?? 'ended';
          _endCall(reason: reason);
        },
      )
      ..subscribe();

    // Foreground service: keeps audio alive when screen locks or user switches apps.
    // Audio focus listener: mutes Agora when a phone call comes in.
    _audioManager.onMuteChanged = _handlePhoneCallMute;
    await _audioManager.start();

    // Countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining == 30 && !_showWarning) {
          _showWarning = true;
          HapticFeedback.mediumImpact();
        }
        if (_remaining <= 0) _endCall(reason: 'timer');
      });
    });

    if (mounted) setState(() => _joining = false);
    _loadFriendStatus();
  }

  Future<void> _loadFriendStatus() async {
    if (widget.event.partnerId.isEmpty) return;
    try {
      final s = await _friendService.getFriendshipStatus(widget.event.partnerId);
      if (mounted) setState(() => _friendStatus = s);
    } catch (_) {}
  }

  Future<void> _addFriend() async {
    if (widget.event.partnerId.isEmpty) return;
    try {
      await _friendService.sendRequest(widget.event.partnerId);
      if (mounted) setState(() => _friendStatus = 'pending');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {}
  }

  Future<void> _confirmEndCall() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B4E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'End Call?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to end this call?',
          style: TextStyle(color: Color(0xFFB8B0CC)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay', style: TextStyle(color: Color(0xFF7C3AED))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('End Call'),
          ),
        ],
      ),
    );
    if (confirm == true) _endCall(reason: 'manual');
  }

  bool _ended = false;

  Future<void> _endCall({String reason = 'manual'}) async {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();

    // Unsubscribe Realtime room channel first so we don't re-enter on our own broadcast.
    final ch = _roomChannel;
    _roomChannel = null;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }

    // Stop foreground service + audio focus listener.
    await _audioManager.stop();

    // Tell the backend to close the call and notify the partner.
    final token = _auth.accessToken;
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$kBackendUrl/call/end'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'channel_name': widget.event.channelName,
            'reason': reason,
          }),
        );
      } catch (_) {}
    }

    await _callService.leaveCall();
    if (mounted) context.go('/home');
  }

  // Called by CallAudioManager when a phone call starts/ends.
  void _handlePhoneCallMute(bool muted) {
    if (!mounted) return;
    setState(() => _phoneCallActive = muted);
    // Phone call started → force-mute Agora regardless of user's mic setting.
    // Phone call ended  → restore to user's setting.
    _callService.setMicMuted(!_micEnabled || muted);
  }

  Future<void> _toggleMic() async {
    final next = !_micEnabled;
    setState(() => _micEnabled = next);
    // If a phone call is active, just save the preference — don't unmute Agora yet.
    if (!_phoneCallActive) {
      await _callService.setMicMuted(!next);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Mic unmuted' : 'Mic muted'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF2D1B4E),
      ),
    );
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerEnabled;
    await _callService.setSpeakerphone(next);
    if (!mounted) return;
    setState(() => _speakerEnabled = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Speaker on' : 'Speaker off'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF2D1B4E),
      ),
    );
  }

  String _formatTime(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _headphonesConnected =>
      _audioRoute == _kRouteHeadset ||
      _audioRoute == _kRouteHeadsetNoMic ||
      _audioRoute == _kRouteBluetooth;

  String get _earbdsLabel {
    if (_audioRoute == _kRouteBluetooth) return 'BT';
    if (_audioRoute == _kRouteHeadset || _audioRoute == _kRouteHeadsetNoMic) return 'Earbuds';
    return 'Earpiece';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioManager.stop();
    final ch = _roomChannel;
    _roomChannel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch).ignore();
    }
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _callService.leaveCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0B2E), Color(0xFF2D1B4E)],
          ),
        ),
        child: SafeArea(
          child: _joining ? _buildConnecting() : _buildCallUI(),
        ),
      ),
    );
  }

  // ── Connecting screen ────────────────────────────────────────────────────────

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimary.withOpacity(0.25),
                border: Border.all(color: kPrimary.withOpacity(0.5), width: 2),
              ),
              child: const Icon(Icons.phone, color: Colors.white, size: 38),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Connecting...',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Setting up voice call',
            style: TextStyle(color: Color(0xFFB8B0CC), fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Main call UI ─────────────────────────────────────────────────────────────

  Widget _buildCallUI() {
    final partner = widget.event.partner;

    return Column(
      children: [
        // ── Timer — subtle, top center ────────────────────────────────────────
        const SizedBox(height: 16),
        Text(
          _formatTime(_remaining),
          style: TextStyle(
            color: _showWarning ? const Color(0xFFFF6B6B) : Colors.white54,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            letterSpacing: 2,
          ),
        ),
        if (_showWarning)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '⚠  Ending soon',
              style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
            ),
          ),

        const SizedBox(height: 28),

        // ── Partner avatar ────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            scale: _partnerSpeaking ? _pulseAnim.value : 1.0,
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _partnerSpeaking ? 136 : 124,
                height: _partnerSpeaking ? 136 : 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(_partnerSpeaking ? 0.55 : 0.2),
                      blurRadius: _partnerSpeaking ? 28 : 12,
                      spreadRadius: _partnerSpeaking ? 5 : 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kPrimary),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1A0B2E),
                ),
                child: ClipOval(
                  child: UserAvatar(
                    name: partner.name,
                    imageUrl: partner.avatarUrl,
                    radius: 55,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // ── Partner name ──────────────────────────────────────────────────────
        Text(
          partner.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        // ── Age / gender ──────────────────────────────────────────────────────
        if (partner.age != null || partner.gender != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (partner.age != null) '${partner.age}',
              if (partner.gender != null) partner.gender!,
            ].join(' · '),
            style: const TextStyle(color: Color(0xFFB8B0CC), fontSize: 13),
          ),
        ],

        // ── Bio ───────────────────────────────────────────────────────────────
        if (partner.bio != null && partner.bio!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              partner.bio!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB8B0CC),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],

        const Spacer(),

        // ── Friend row ────────────────────────────────────────────────────────
        _buildFriendRow(),

        const SizedBox(height: 22),

        // ── 3 control buttons ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlBtn(
                icon: _micEnabled ? Icons.mic : Icons.mic_off,
                label: _micEnabled ? 'Mic' : 'Muted',
                active: !_micEnabled,
                activeColor: const Color(0xFFEF4444),
                onTap: _toggleMic,
              ),
              _ControlBtn(
                icon: _speakerEnabled ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                label: 'Speaker',
                active: _speakerEnabled,
                activeColor: kPrimary,
                onTap: _toggleSpeaker,
              ),
              // Earbuds — auto-detected, no manual tap
              _ControlBtn(
                icon: _headphonesConnected ? Icons.headphones : Icons.headset_off,
                label: _earbdsLabel,
                active: _headphonesConnected,
                activeColor: kPrimary,
                onTap: null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // ── End call button ───────────────────────────────────────────────────
        Column(
          children: [
            GestureDetector(
              onTap: _confirmEndCall,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEF4444),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.45),
                      blurRadius: 22,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 8),
            const Text('End Call', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildFriendRow() {
    if (_friendStatus == null) {
      return TextButton.icon(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add_outlined, color: kPrimary, size: 18),
        label: const Text('Add Friend', style: TextStyle(color: kPrimary, fontSize: 14)),
      );
    }
    if (_friendStatus == 'pending') {
      return const Text(
        'Request Sent',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      );
    }
    if (_friendStatus == 'accepted') {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people, color: Colors.greenAccent, size: 16),
          SizedBox(width: 5),
          Text('Friends', style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

// ── Reusable control button ───────────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? activeColor : Colors.white.withOpacity(0.1),
              border: Border.all(
                color: active ? activeColor : Colors.white24,
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white70 : Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
