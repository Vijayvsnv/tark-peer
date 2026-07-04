import 'dart:async';
import 'dart:convert';
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
import '../../services/update_service.dart';
import '../../widgets/filter_bottom_sheet.dart';
import '../../widgets/user_avatar.dart';
import 'games_tab.dart';
import 'learn_tab.dart';
import 'progress_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
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
    _hints.ensureLoaded();
    _loadAll();
    _statsTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadWaiting());
    Future.delayed(const Duration(seconds: 2), _checkUpdate);
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
    } catch (_) {}
  }

  Future<void> _loadPendingCount() async {
    try {
      final count = await _friendService.getPendingCount();
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
  void dispose() {
    _incomingCallSub?.cancel();
    DirectCallService.instance.unsubscribe();
    _presenceService.setOffline();
    _pulseCtrl.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _showNotifications() async {
    final requests = await _friendService.getPendingRequests();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationsSheet(
        requests: requests,
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
            child: UserAvatar(
              name: _profile?.name ?? 'U',
              imageUrl: _profile?.avatarUrl,
              radius: 18,
            ),
          ),
        ),
        title: Image.asset(
          'assets/Tark-pear-logo-change.png',
          height: 175,
          fit: BoxFit.contain,
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
              if (i == 2) _hints.markGamesSeen();
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
              children: [
                SizedBox(height: profileIncomplete ? 40 : 80),
                const Text(
                  'PRACTICE WITH HUMANS',
                  style: TextStyle(
                    color: kPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect with real people and practice',
                  style: TextStyle(color: kTextSecondary, fontSize: 15),
                ),
                const Spacer(),
                Center(
                  child: Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _hints.tarkSeen,
                        builder: (_, seen, __) => seen
                            ? const SizedBox(height: 0)
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
                      const SizedBox(height: 24),
                      const Text(
                        'Tap to find a random partner',
                        style: TextStyle(color: kTextSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      _LiveStatsRow(
                        waiting: _waiting,
                        online: _online,
                        inCall: _inCall,
                      ),
                      const SizedBox(height: 24),
                      const _PeakHoursCard(),
                    ],
                  ),
                ),
                const Spacer(),
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
    ('Lunch', '12:30 PM – 1:30 PM'),
    ('Break', '3:00 PM – 4:00 PM'),
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
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      _sessions[i].$1,
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
  final List<Map<String, dynamic>> requests;
  final FriendService friendService;
  final VoidCallback onDone;

  const _NotificationsSheet({
    required this.requests,
    required this.friendService,
    required this.onDone,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late List<Map<String, dynamic>> _requests;

  @override
  void initState() {
    super.initState();
    _requests = List.from(widget.requests);
  }

  Future<void> _accept(String id, int index) async {
    await widget.friendService.acceptRequest(id);
    setState(() => _requests.removeAt(index));
    if (_requests.isEmpty) widget.onDone();
  }

  Future<void> _reject(String id, int index) async {
    await widget.friendService.rejectRequest(id);
    setState(() => _requests.removeAt(index));
    if (_requests.isEmpty) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: kTextSecondary.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Friend Requests', style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: _requests.isEmpty
                ? const Center(child: Text('No pending requests', style: TextStyle(color: kTextSecondary)))
                : ListView.builder(
                    controller: ctrl,
                    itemCount: _requests.length,
                    itemBuilder: (_, i) {
                      final req = _requests[i];
                      final requester = req['requester'] as Map<String, dynamic>? ?? {};
                      final name = requester['name'] as String? ?? 'User';
                      final avatar = requester['avatar_url'] as String?;
                      final reqId = req['id'] as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kPrimary,
                          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                          child: avatar == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
                        ),
                        title: Text(name, style: const TextStyle(color: kTextPrimary)),
                        subtitle: const Text('Wants to be your friend', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () => _accept(reqId, i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () => _reject(reqId, i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Incoming Call Dialog ──────────────────────────────────────────────────────

class _IncomingCallDialog extends StatefulWidget {
  final String callerName;
  final String? callerAvatar;

  const _IncomingCallDialog({required this.callerName, this.callerAvatar});

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
      if (mounted) Navigator.of(context, rootNavigator: true).pop(false);
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
