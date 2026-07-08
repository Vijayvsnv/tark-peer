import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/block_service.dart';
import '../../widgets/user_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _blockService = BlockService();
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _blockService.getBlockedUsers();
      if (mounted) setState(() { _blocked = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Unblock User',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Unblock $name? They will be able to match with you again.',
          style: const TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _blockService.unblockUser(userId);
      if (mounted) {
        setState(() => _blocked.removeWhere((b) => b['blocked_id'] == userId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name unblocked'), backgroundColor: kSuccess),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unblock. Please try again.'), backgroundColor: Colors.red),
        );
      }
    }
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
        title: const Text(
          'Blocked Users',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _blocked.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, color: kTextMuted, size: 52),
                      const SizedBox(height: 14),
                      const Text(
                        'No blocked users',
                        style: TextStyle(color: kTextSecondary, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Users you block will appear here.',
                        style: TextStyle(color: kTextMuted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blocked.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final item = _blocked[i];
                    final profile = item['profile'] as Map<String, dynamic>?;
                    final userId = item['blocked_id'] as String;
                    final name = (profile?['name'] as String?) ?? 'Unknown';
                    final avatarUrl = profile?['avatar_url'] as String?;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kBorder),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(name: name, imageUrl: avatarUrl, radius: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: kTextPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _unblock(userId, name),
                            style: TextButton.styleFrom(
                              foregroundColor: kPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
