import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
import '../../services/rating_service.dart';
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
  final _ratingService = RatingService();
  final _auth = AuthService();

  int _elapsed = 0;
  Timer? _timer;
  RealtimeChannel? _roomChannel;

  bool _micEnabled = true;
  bool _speakerEnabled = false;
  bool _phoneCallActive = false;
  int _audioRoute = -1;

  bool _joining = true;
  bool _partnerSpeaking = false;
  String? _friendStatus;

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
                backgroundColor: kSuccess,
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

    // Elapsed timer — counts up, auto-disconnects at 100 min
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= kMaxCallDurationSeconds) _endCall(reason: 'timer');
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
        backgroundColor: kCallBgBottom,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'End Call?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to end this call?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay', style: TextStyle(color: kCyan, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('End Call'),
          ),
        ],
      ),
    );
    if (confirm == true) _endCall(reason: 'manual');
  }

  bool _ended = false;

  Future<void> _endCall({
    String reason = 'manual',
    String navigateTo = '/home',
    bool askRating = true,
  }) async {
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
    if (!mounted) return;

    // Ask user to rate the partner — only if the call actually happened
    // (>= 5 seconds) and we have a partner id to attribute the rating to.
    if (askRating && _elapsed >= 5 && widget.event.partnerId.isNotEmpty) {
      await _showRatingDialog();
    }
    if (mounted) context.go(navigateTo);
  }

  void _skipCall() {
    // End current call and jump straight into matching for a new partner.
    // No rating prompt — skip should feel instant.
    _endCall(reason: 'skip', navigateTo: '/matching', askRating: false);
  }

  Future<void> _showRatingDialog() async {
    int selected = 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: kCallBgBottom,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rate your call with',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                widget.event.partner.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final idx = i + 1;
                  final filled = idx <= selected;
                  return IconButton(
                    onPressed: () => setDialogState(() => selected = idx),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: filled ? const Color(0xFFFFC933) : Colors.white70,
                      size: 38,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: selected == 0
                        ? null
                        : () async {
                            Navigator.pop(dialogCtx);
                            await _ratingService.rate(
                              channelName: widget.event.channelName,
                              ratedUserId: widget.event.partnerId,
                              stars: selected,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCyan,
                      disabledBackgroundColor: kCyan.withOpacity(0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        backgroundColor: kCallBgBottom,
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
        backgroundColor: kCallBgBottom,
      ),
    );
  }

  String _formatElapsed(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
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
            colors: [kCallBgTop, kCallBgBottom],
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
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kCyan.withOpacity(0.18),
                border: Border.all(color: kCyan.withOpacity(0.6), width: 2),
              ),
              child: const Icon(Icons.phone, color: Colors.white, size: 40),
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
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
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
        // ── Elapsed time — subtle, top center ────────────────────────────────
        const SizedBox(height: 16),
        Text(
          _formatElapsed(_elapsed),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            letterSpacing: 2,
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
                width: _partnerSpeaking ? 140 : 126,
                height: _partnerSpeaking ? 140 : 126,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kCyan.withOpacity(_partnerSpeaking ? 0.6 : 0.18),
                      blurRadius: _partnerSpeaking ? 32 : 14,
                      spreadRadius: _partnerSpeaking ? 6 : 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: kCyan),
              ),
              Container(
                width: 112,
                height: 112,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCallBgTop,
                ),
                child: ClipOval(
                  child: UserAvatar(
                    name: partner.name,
                    imageUrl: partner.avatarUrl,
                    radius: 56,
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

        // ── Location (state, country) ─────────────────────────────────────────
        if (partner.state != null || partner.country != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_outlined,
                  color: Color(0xFFB8B0CC), size: 13),
              const SizedBox(width: 4),
              Text(
                [
                  if (partner.state != null) partner.state!,
                  if (partner.country != null) partner.country!,
                ].join(', '),
                style: const TextStyle(color: Color(0xFFB8B0CC), fontSize: 13),
              ),
            ],
          ),
        ],

        // ── Occupation / sector ───────────────────────────────────────────────
        if (partner.occupation != null || partner.sector != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              [
                if (partner.occupation != null && partner.occupation!.trim().isNotEmpty)
                  partner.occupation!,
                if (partner.sector != null) partner.sector!,
              ].join(' · '),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB8B0CC), fontSize: 13),
            ),
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
                activeColor: kDanger,
                onTap: _toggleMic,
              ),
              _ControlBtn(
                icon: _speakerEnabled ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                label: 'Speaker',
                active: _speakerEnabled,
                activeColor: kCyan,
                onTap: _toggleSpeaker,
              ),
              // Earbuds — auto-detected, no manual tap
              _ControlBtn(
                icon: _headphonesConnected ? Icons.headphones : Icons.headset_off,
                label: _earbdsLabel,
                active: _headphonesConnected,
                activeColor: kCyan,
                onTap: null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // ── End call + Skip buttons ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _EndActionBtn(
                icon: Icons.call_end,
                label: 'End',
                bgColor: const Color(0xFFEF4444),
                glowColor: Colors.red.withOpacity(0.45),
                onTap: _confirmEndCall,
              ),
              _EndActionBtn(
                icon: Icons.skip_next_rounded,
                label: 'Next',
                bgColor: kCyan,
                glowColor: kCyan.withOpacity(0.45),
                onTap: _skipCall,
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildFriendRow() {
    if (_friendStatus == null) {
      return ElevatedButton.icon(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white, size: 18),
        label: const Text('Add Friend', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      );
    }
    if (_friendStatus == 'pending') {
      return const Text(
        'Request Sent',
        style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
      );
    }
    if (_friendStatus == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kSuccess.withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people, color: kSuccess, size: 16),
            SizedBox(width: 6),
            Text('Friends', style: TextStyle(color: kSuccess, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
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

class _EndActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color glowColor;
  final VoidCallback onTap;

  const _EndActionBtn({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.glowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              boxShadow: [
                BoxShadow(color: glowColor, blurRadius: 18, spreadRadius: 3),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
