import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/friend_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/partner_profile_sheet.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _profileService = ProfileService();
  final _friendService = FriendService();
  final _auth = AuthService();
  List<Map<String, dynamic>> _calls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _profileService.getCallHistory();
      if (mounted) setState(() { _calls = c; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getPartnerName(Map<String, dynamic> call) {
    final myId = _auth.currentUser?.id ?? '';
    if (call['user_a'] == myId) return call['user_b_profile']?['name'] as String? ?? 'Unknown';
    return call['user_a_profile']?['name'] as String? ?? 'Unknown';
  }

  String? _getPartnerId(Map<String, dynamic> call) {
    final myId = _auth.currentUser?.id ?? '';
    if (call['user_a'] == myId) return call['user_b'] as String?;
    return call['user_a'] as String?;
  }

  Map<String, dynamic>? _getPartnerProfile(Map<String, dynamic> call) {
    final myId = _auth.currentUser?.id ?? '';
    if (call['user_a'] == myId) return call['user_b_profile'] as Map<String, dynamic>?;
    return call['user_a_profile'] as Map<String, dynamic>?;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '—';
    final m = seconds ~/ 60;
    if (m == 0) return '<1 min';
    return '$m min';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _showPartnerProfile(String partnerId, Map<String, dynamic>? profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PartnerProfileSheet(
        partnerId: partnerId,
        name: profile?['name'] as String? ?? 'User',
        bio: profile?['bio'] as String?,
        occupation: profile?['occupation'] as String?,
        sector: profile?['sector'] as String?,
        country: profile?['country'] as String?,
        state: profile?['state'] as String?,
        friendService: _friendService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Recent Calls', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _calls.isEmpty
              ? const Center(
                  child: Text(
                    'No calls yet',
                    style: TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  itemCount: _calls.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final call = _calls[i];
                    final name = _getPartnerName(call);
                    final partnerId = _getPartnerId(call);
                    final profile = _getPartnerProfile(call);
                    final duration = _formatDuration(call['duration_seconds'] as int?);
                    final date = _formatDate(call['started_at'] as String?);
                    return InkWell(
                      onTap: partnerId != null
                          ? () => _showPartnerProfile(partnerId, profile)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: kPrimaryLight,
                              radius: 22,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      if (date.isNotEmpty) ...[
                                        Text(date, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                                        const SizedBox(width: 6),
                                        const Text('•', style: TextStyle(color: kTextMuted, fontSize: 12)),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(duration, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: kTextMuted, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
