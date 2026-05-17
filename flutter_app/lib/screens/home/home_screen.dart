import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/friend_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/user_avatar.dart';
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
  UserProfile? _profile;
  int _currentTab = 1;
  int _pendingCount = 0;
  int _waiting = 0;
  Timer? _statsTimer;
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
    _loadAll();
    _statsTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadWaiting());
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProfile(), _loadPendingCount(), _loadWaiting()]);
  }

  Future<void> _loadWaiting() async {
    try {
      final resp = await http.get(Uri.parse('$kBackendUrl/stats'));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _waiting = (data['waiting'] as num?)?.toInt() ?? 0);
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

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _statsTimer?.cancel();
    super.dispose();
  }

  Future<void> _showNotifications() async {
    final requests = await _friendService.getPendingRequests();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
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
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: kTextSecondary),
              onPressed: _showNotifications,
            ),
            if (_pendingCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      '$_pendingCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: const Text(
          'Tark Peer',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: UserAvatar(
                name: _profile?.name ?? 'U',
                imageUrl: _profile?.avatarUrl,
                radius: 18,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildComingSoon('Learn', Icons.book_outlined),
          _buildPracticeTab(),
          const ProgressTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        backgroundColor: kSurface,
        selectedItemColor: kPrimary,
        unselectedItemColor: kTextSecondary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book_outlined), label: 'Learn'),
          BottomNavigationBarItem(icon: Icon(Icons.mic_outlined), label: 'Practice'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Progress'),
        ],
      ),
    );
  }

  Widget _buildPracticeTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Practice with Humans',
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect with real people and practice',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _waiting > 0
                  ? Container(
                      key: ValueKey(_waiting),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_waiting ${_waiting == 1 ? 'person' : 'people'} waiting right now',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(key: ValueKey(0), height: 0),
            ),
            const SizedBox(height: 32),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
              child: _FindPartnerButton(onTap: () => context.go('/matching')),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap to find a random partner',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoon(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: kPrimary.withOpacity(0.4), size: 64),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Coming soon...', style: TextStyle(color: kTextSecondary, fontSize: 14)),
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
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFF9F67FF), kPrimary]),
          boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.5), blurRadius: 30, spreadRadius: 10)],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, color: Colors.white, size: 48),
            SizedBox(height: 8),
            Text(
              'Find\nPartner',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

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
