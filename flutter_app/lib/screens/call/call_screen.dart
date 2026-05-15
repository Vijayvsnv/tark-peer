import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme.dart';
import '../../models/match_event.dart';
import '../../services/call_service.dart';
import '../../services/match_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/user_avatar.dart';
import '../../core/constants.dart';

class CallScreen extends StatefulWidget {
  final MatchEvent event;
  const CallScreen({super.key, required this.event});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _callService = CallService();
  final _matchService = MatchService();
  final _auth = AuthService();
  int _remaining = kCallDurationSeconds;
  Timer? _timer;
  StreamSubscription? _sub;
  bool _micEnabled = true;
  bool _joining = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
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

    try {
      await _callService.joinCall(
        appId: widget.event.agoraAppId,
        channelName: widget.event.channelName,
        token: widget.event.agoraToken,
        uid: widget.event.agoraUid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join call: $e'), backgroundColor: Colors.red),
        );
        context.go('/home');
        return;
      }
    }

    final token = _auth.accessToken;
    if (token != null) {
      await _matchService.connect(token);
      _sub = _matchService.events.listen(_onWsEvent);
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _endCall(reason: 'timer');
    });

    if (mounted) setState(() => _joining = false);
  }

  void _onWsEvent(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'call_ended') {
      final reason = msg['reason'] as String? ?? 'ended';
      _endCall(reason: reason);
    }
  }

  Future<void> _endCall({String reason = 'manual'}) async {
    _timer?.cancel();
    _sub?.cancel();
    _matchService.sendEndCall();
    await _callService.leaveCall();
    await _matchService.disconnect();
    if (mounted) context.go('/home');
  }

  Future<void> _toggleMic() async {
    await _callService.toggleMic();
    setState(() => _micEnabled = !_micEnabled);
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _callService.leaveCall();
    _matchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.event.partner;
    final progress = _remaining / kCallDurationSeconds;

    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: _joining
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('In Call', style: TextStyle(color: kTextSecondary, fontSize: 14)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: _remaining < 30 ? Colors.red : kPrimary,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatTime(_remaining),
                                style: TextStyle(
                                  color: _remaining < 30 ? Colors.red : kTextPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: kSurface,
                      valueColor: AlwaysStoppedAnimation(
                        _remaining < 30 ? Colors.red : kPrimary,
                      ),
                    ),
                    const SizedBox(height: 60),
                    UserAvatar(
                      name: partner.name,
                      imageUrl: partner.avatarUrl,
                      radius: 60,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      partner.name,
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (partner.age != null || partner.gender != null)
                      Text(
                        [
                          if (partner.age != null) '${partner.age} years',
                          if (partner.gender != null) partner.gender!,
                        ].join(' • '),
                        style: const TextStyle(color: kTextSecondary, fontSize: 16),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.green, size: 8),
                          SizedBox(width: 6),
                          Text('Connected', style: TextStyle(color: Colors.green, fontSize: 13)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          icon: _micEnabled ? Icons.mic : Icons.mic_off,
                          label: _micEnabled ? 'Mute' : 'Unmute',
                          color: _micEnabled ? kSurface : Colors.orange,
                          onTap: _toggleMic,
                        ),
                        _ControlButton(
                          icon: Icons.call_end,
                          label: 'End Call',
                          color: Colors.red,
                          size: 80,
                          onTap: () => _endCall(reason: 'manual'),
                        ),
                        const SizedBox(width: 64),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
      ],
    );
  }
}
