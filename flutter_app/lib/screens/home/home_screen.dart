import 'dart:async';
import 'dart:convert';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../models/match_event.dart';
import '../../services/auth_service.dart';
import '../../services/direct_call_service.dart';
import '../../services/friend_service.dart';
import '../../services/home_hints_service.dart';
import '../../services/profile_service.dart';
import '../../services/presence_service.dart';
import '../../services/fcm_service.dart';
import '../../services/notification_service.dart';
import '../../services/review_service.dart';
import '../../services/update_service.dart';
import '../../widgets/filter_bottom_sheet.dart';
import '../../widgets/user_avatar.dart';
import 'ai_tab.dart';
import 'games_tab.dart';
import 'learn_tab.dart';
import 'progress_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _auth = AuthService();
  final _profileService = ProfileService();
  final _friendService = FriendService();
  final _presenceService = PresenceService();
  final _hints = HomeHintsService();
  UserProfile? _profile;
  int _currentTab = 1;
  DateTime? _lastBackPress;
  int _pendingCount = 0;
  int _waiting = 0;
  int _online = 0;
  int _inCall = 0;
  Timer? _statsTimer;
  StreamSubscription? _incomingCallSub;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addObserver(this);
    _hints.ensureLoaded();
    _loadAll();
    _statsTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadWaiting());
    Future.delayed(const Duration(seconds: 2), _checkUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ReviewService.pendingCheck && mounted) {
        ReviewService.pendingCheck = false;
        ReviewService.instance.maybeAsk(context);
      }
    });
    FcmService.instance.init();
    _presenceService.setOnline();
    DirectCallService.instance.subscribe();
    _incomingCallSub = DirectCallService.instance.incomingCalls.listen(_onIncomingCall);
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProfile(), _loadPendingCount(), _loadWaiting()]);
  }

  Future<void> _loadWaiting() async {
    try {
      final resp = await http.get(Uri.parse('$kBackendUrl/stats'));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // active_calls = number of rooms; users in call = rooms × 2
        final rooms = (data['active_calls'] as num?)?.toInt() ?? 0;
        setState(() {
          _waiting = (data['waiting'] as num?)?.toInt() ?? 0;
          _online = (data['online'] as num?)?.toInt() ?? 0;
          _inCall = rooms * 2;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _profileService.getMyProfile();
      if (mounted) setState(() => _profile = p);
      if (p != null) {
        try {
          await FirebaseCrashlytics.instance.setUserIdentifier(p.id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _loadPendingCount() async {
    try {
      final count = await NotificationService.instance.getUnreadCount();
      if (mounted) setState(() => _pendingCount = count);
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    if (!mounted) return;
    final info = await UpdateService().checkForUpdate();
    if (info == null || !mounted) return;
    _showUpdateDialog(info['version']!, info['url']!);
  }

  void _showUpdateDialog(String version, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(version: version, downloadUrl: url),
    );
  }

  Future<void> _onIncomingCall(Map<String, dynamic> data) async {
    if (!mounted) return;
    final callerName = (data['partner'] as Map?)?['name'] as String? ?? 'Someone';
    final callerAvatar = (data['partner'] as Map?)?['avatar_url'] as String?;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _IncomingCallDialog(
        callerName: callerName,
        callerAvatar: callerAvatar,
        callerId: data['partner_id'] as String? ?? '',
        onAutoDeclined: () => NotificationService.instance.insertMissedCall(
          callerName: callerName,
          callerId: data['partner_id'] as String? ?? '',
          callerAvatar: callerAvatar,
        ),
      ),
    );

    if (accepted == true && mounted) {
      final event = MatchEvent(
        channelName: data['channel_name'] as String,
        agoraToken: data['agora_token'] as String,
        agoraUid: data['agora_uid'] as int,
        agoraAppId: data['agora_app_id'] as String,
        partnerId: data['partner_id'] as String,
        partner: PartnerInfo.fromJson(
          (data['partner'] as Map).cast<String, dynamic>(),
        ),
      );
      context.push('/call', extra: event);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _presenceService.setOffline();
    } else if (state == AppLifecycleState.resumed) {
      _presenceService.setOnline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSub?.cancel();
    DirectCallService.instance.unsubscribe();
    _presenceService.setOffline();
    _pulseCtrl.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _showNotifications() async {
    final notifications = await NotificationService.instance.getAll();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationsSheet(
        notifications: notifications,
        friendService: _friendService,
        onDone: () {
          _loadPendingCount();
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        toolbarHeight: 72,
        leading: GestureDetector(
          onTap: () => context.push('/profile'),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                UserAvatar(
                  name: _profile?.name ?? 'U',
                  imageUrl: _profile?.avatarUrl,
                  radius: 18,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
                    const SizedBox(width: 3),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
                    const SizedBox(width: 3),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
                  ],
                ),
              ],
            ),
          ),
        ),
        title: Transform.translate(
          offset: const Offset(0, -5),
          child: Image.asset(
            'assets/Tark-pear-logo-change.png',
            height: 175,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => context.push('/chat'),
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chat_bubble_outline_rounded, color: kPrimary, size: 26),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: kTextPrimary),
                onPressed: _showNotifications,
              ),
              if (_pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        '$_pendingCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          const LearnTab(),
          _buildPracticeTab(),
          const AiTab(),
          const GamesTab(),
          const ProgressTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kBackground,
          border: Border(top: BorderSide(color: kBorder, width: 1)),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([_hints.learnSeen, _hints.gamesSeen]),
          builder: (_, __) => BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (i) {
              setState(() => _currentTab = i);
              if (i == 0) _hints.markLearnSeen();
              if (i == 3) _hints.markGamesSeen();
            },
            backgroundColor: kBackground,
            selectedItemColor: kPrimary,
            unselectedItemColor: kTextMuted,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            items: [
              BottomNavigationBarItem(
                icon: _PulseTabIcon(icon: Icons.book_outlined, showPulse: !_hints.learnSeen.value),
                label: 'Learn',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.mic_outlined), label: 'Practice'),
              const BottomNavigationBarItem(
                icon: Icon(Icons.smart_toy_rounded),
                label: 'AI Talk',
              ),
              BottomNavigationBarItem(
                icon: _PulseTabIcon(icon: Icons.games_rounded, showPulse: !_hints.gamesSeen.value),
                label: 'Games',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Progress'),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildPracticeTab() {
    final profileIncomplete = _profile != null && !_profile!.isProfileComplete;
    return Column(
      children: [
        if (profileIncomplete)
          _ProfileIncompleteBanner(onTap: () => context.push('/setup')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'PRACTICE WITH HUMANS',
                  style: TextStyle(
                    color: kPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<bool>(
                  valueListenable: _hints.tarkSeen,
                  builder: (_, seen, __) => seen
                      ? const SizedBox.shrink()
                      : const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: _TarkHereHint(),
                        ),
                ),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
                  child: _FindPartnerButton(onTap: () async {
                    _hints.markTarkSeen();
                    final filter = await showFilterSheet(context);
                    if (filter != null && context.mounted) {
                      context.push('/matching', extra: filter);
                    }
                  }),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tap to find a random partner',
                  style: TextStyle(color: kTextSecondary, fontSize: 14),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => context.push('/ai-call', extra: 'home_button'),
                  icon: const Text('🤖', style: TextStyle(fontSize: 15)),
                  label: const Text(
                    'Practice with Shivani (AI Partner)',
                    style: TextStyle(
                      color: kPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kPrimary.withOpacity(0.5), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                _LiveStatsRow(
                  waiting: _waiting,
                  online: _online,
                  inCall: _inCall,
                ),
                const SizedBox(height: 14),
                const _PeakHoursCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComingSoon(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: kTextMuted, size: 64),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Coming soon...', style: TextStyle(color: kTextSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

class _LiveStatsRow extends StatelessWidget {
  final int waiting;
  final int online;
  final int inCall;

  const _LiveStatsRow({
    required this.waiting,
    required this.online,
    required this.inCall,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _StatPill(dot: const Color(0xFFF97316), count: waiting, label: 'waiting'),
        _StatPill(dot: const Color(0xFF22C55E), count: online,  label: 'online'),
        _StatPill(dot: const Color(0xFF8B5CF6), count: inCall,  label: 'in call'),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final Color dot;
  final int count;
  final String label;

  const _StatPill({required this.dot, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: kTextSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PeakHoursCard extends StatelessWidget {
  const _PeakHoursCard();

  static const _sessions = [
    ('Evening', '8:00 PM – 9:00 PM'),
  ];

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF2563EB);
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.05),
        border: Border.all(color: cardColor.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_outlined, size: 18, color: cardColor),
                SizedBox(width: 8),
                Text(
                  'Peak Hours',
                  style: TextStyle(
                    color: cardColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  '— Best time to match',
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < _sessions.length; i++) ...[
            if (i > 0) Divider(height: 1, color: cardColor.withOpacity(0.12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _sessions[i].$1,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _sessions[i].$2,
                    style: const TextStyle(
                      color: kTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
              border: Border(top: BorderSide(color: cardColor.withOpacity(0.12))),
            ),
            child: const Text(
              'More users are active during these hours',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileIncompleteBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileIncompleteBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.10),
            border: Border(bottom: BorderSide(color: kPrimary.withOpacity(0.25))),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: kPrimary, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Complete your profile to get better matches',
                  style: TextStyle(
                    color: kPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(
                'Complete',
                style: TextStyle(
                  color: kPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right, color: kPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarkHereHint extends StatefulWidget {
  const _TarkHereHint();

  @override
  State<_TarkHereHint> createState() => _TarkHereHintState();
}

class _TarkHereHintState extends State<_TarkHereHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kPrimary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Text(
            'Tap here to find your first partner!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _bounce,
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _bounce.value),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: kPrimary,
              size: 32,
            ),
          ),
        ),
      ],
    );
  }
}

class _PulseTabIcon extends StatefulWidget {
  final IconData icon;
  final bool showPulse;

  const _PulseTabIcon({required this.icon, required this.showPulse});

  @override
  State<_PulseTabIcon> createState() => _PulseTabIconState();
}

class _PulseTabIconState extends State<_PulseTabIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showPulse) return Icon(widget.icon);
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Icon(widget.icon)),
          Positioned(
            top: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = _ctrl.value;
                final size = 8 + 4 * t;
                final opacity = (1 - t).clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: kDanger.withOpacity(0.35 * opacity),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: kDanger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FindPartnerButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FindPartnerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccentSoft, kAccent],
          ),
          boxShadow: [
            BoxShadow(
              color: kAccent.withOpacity(0.35),
              blurRadius: 32,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, color: Colors.white, size: 52),
            SizedBox(height: 8),
            Text(
              'Tark Here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Update Dialog ─────────────────────────────────────────────────────────────

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String downloadUrl;
  const _UpdateDialog({required this.version, required this.downloadUrl});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  Future<void> _update() async {
    Navigator.pop(context);
    await UpdateService().openDownloadUrl(widget.downloadUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.system_update, color: kAccent, size: 22),
          SizedBox(width: 10),
          Text('Update Available', style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Text(
        'Version ${widget.version} available.\nBrowser mein download hoga, phir install karo.',
        style: const TextStyle(color: kTextSecondary, fontSize: 14),
      ),
      actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later', style: TextStyle(color: kTextSecondary)),
              ),
              ElevatedButton(
                onPressed: _update,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Update Now'),
              ),
            ],
    );
  }
}

// ── Notifications Sheet ───────────────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final FriendService friendService;
  final VoidCallback onDone;

  const _NotificationsSheet({
    required this.notifications,
    required this.friendService,
    required this.onDone,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.notifications);
    NotificationService.instance.markAllRead();
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Future<void> _acceptFriend(Map<String, dynamic> notif) async {
    final data = (notif['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final fid = data['friendship_id'] as String?;
    if (fid == null) return;
    await widget.friendService.acceptRequest(fid);
    await NotificationService.instance.deleteById(notif['id'] as String);
    setState(() => _items.removeWhere((n) => n['id'] == notif['id']));
  }

  Future<void> _rejectFriend(Map<String, dynamic> notif) async {
    final data = (notif['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final fid = data['friendship_id'] as String?;
    if (fid == null) return;
    await widget.friendService.rejectRequest(fid);
    await NotificationService.instance.deleteById(notif['id'] as String);
    setState(() => _items.removeWhere((n) => n['id'] == notif['id']));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.88,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: kTextSecondary.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_items.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await NotificationService.instance.markAllRead();
                      widget.onDone();
                    },
                    child: const Text('Mark all read', style: TextStyle(color: kPrimary, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 52, color: kTextMuted),
                        const SizedBox(height: 12),
                        const Text('No notifications', style: TextStyle(color: kTextSecondary, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: ctrl,
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (_, i) => _buildItem(_items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> notif) {
    final type = notif['type'] as String? ?? '';
    final title = notif['title'] as String? ?? '';
    final body = notif['body'] as String? ?? '';
    final isRead = notif['is_read'] as bool? ?? true;
    final createdAt = notif['created_at'] as String?;
    final data = (notif['data'] as Map?)?.cast<String, dynamic>() ?? {};

    IconData icon;
    Color iconColor;
    Color iconBg;
    switch (type) {
      case 'friend_request':
        icon = Icons.person_add_rounded; iconColor = kPrimary; iconBg = kPrimaryLight;
        break;
      case 'friend_accepted':
        icon = Icons.check_circle_rounded; iconColor = kSuccess; iconBg = kSuccess.withOpacity(0.1);
        break;
      case 'rating_received':
        icon = Icons.star_rounded; iconColor = const Color(0xFFFFC933); iconBg = const Color(0xFFFFC933).withOpacity(0.12);
        break;
      case 'missed_call':
        icon = Icons.phone_missed_rounded; iconColor = kDanger; iconBg = kDanger.withOpacity(0.1);
        break;
      default:
        icon = Icons.notifications_rounded; iconColor = kTextSecondary; iconBg = kSurface;
    }

    return Container(
      color: isRead ? Colors.transparent : kPrimary.withOpacity(0.03),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: kTextPrimary,
                              fontSize: 14,
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(_timeAgo(createdAt), style: const TextStyle(color: kTextMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          if (type == 'friend_request') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 54),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectFriend(notif),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Decline', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptFriend(notif),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 0,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Accept', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
          if (type == 'rating_received') ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Row(
                children: List.generate(5, (i) => Icon(
                  i < ((data['stars'] as num?)?.toInt() ?? 0)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: const Color(0xFFFFC933),
                  size: 18,
                )),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Incoming Call Dialog ──────────────────────────────────────────────────────

class _IncomingCallDialog extends StatefulWidget {
  final String callerName;
  final String? callerAvatar;
  final String callerId;
  final VoidCallback? onAutoDeclined;

  const _IncomingCallDialog({
    required this.callerName,
    this.callerAvatar,
    required this.callerId,
    this.onAutoDeclined,
  });

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ring;
  late Animation<double> _scale;
  Timer? _autoDecline;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _ring, curve: Curves.easeInOut),
    );
    _autoDecline = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        widget.onAutoDeclined?.call();
        Navigator.of(context, rootNavigator: true).pop(false);
      }
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    _autoDecline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Incoming Call',
              style: TextStyle(color: kTextSecondary, fontSize: 13, letterSpacing: 0.5),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _scale,
              builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kPrimary, width: 3),
                ),
                child: ClipOval(
                  child: UserAvatar(
                    name: widget.callerName,
                    imageUrl: widget.callerAvatar,
                    radius: 40,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.callerName,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Calling you...',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  label: 'Decline',
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
                ),
                _CallButton(
                  icon: Icons.call,
                  color: Colors.green,
                  label: 'Accept',
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
