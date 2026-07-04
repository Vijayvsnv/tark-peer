import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/friend_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _friendService = FriendService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await _friendService.getFriends();
      if (mounted) setState(() { _friends = f; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visible {
    if (_query.isEmpty) return _friends;
    return _friends.where((f) {
      final other = f['partner_profile'] as Map<String, dynamic>? ?? {};
      final name = (other['name'] as String? ?? '').toLowerCase();
      return name.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _loading ? 'Friends' : 'Friends (${_friends.length})',
          style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : Column(
              children: [
                if (_friends.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search friends',
                        hintStyle: const TextStyle(color: kTextSecondary),
                        prefixIcon: const Icon(Icons.search, color: kTextSecondary),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, color: kTextSecondary, size: 18),
                                onPressed: () => _searchCtrl.clear(),
                              ),
                        filled: true,
                        fillColor: kSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: kPrimary,
                    onRefresh: _load,
                    child: _friends.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'No friends yet\nStart calling to connect!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: kTextSecondary, fontSize: 14),
                                ),
                              ),
                            ],
                          )
                        : visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  Center(
                                    child: Text(
                                      'No match found',
                                      style: TextStyle(color: kTextSecondary, fontSize: 14),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final f = visible[i];
                                  final other = f['partner_profile'] as Map<String, dynamic>? ?? {};
                                  final name = other['name'] as String? ?? 'Friend';
                                  final avatar = other['avatar_url'] as String?;
                                  final partnerId = other['id'] as String?;
                                  return Material(
                                    color: kSurface,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: partnerId == null
                                          ? null
                                          : () => context.push('/friend/$partnerId'),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 24,
                                              backgroundColor: kPrimaryLight,
                                              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                              child: avatar == null
                                                  ? Text(
                                                      name[0].toUpperCase(),
                                                      style: const TextStyle(color: kPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Text(name, style: const TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: kSuccess.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.people, color: kSuccess, size: 14),
                                                  SizedBox(width: 4),
                                                  Text('Friend', style: TextStyle(color: kSuccess, fontSize: 11, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
    );
  }
}
