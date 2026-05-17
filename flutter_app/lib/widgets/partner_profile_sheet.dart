import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/friend_service.dart';

class PartnerProfileSheet extends StatefulWidget {
  final String partnerId;
  final String name;
  final String? bio;
  final FriendService friendService;

  const PartnerProfileSheet({
    super.key,
    required this.partnerId,
    required this.name,
    required this.bio,
    required this.friendService,
  });

  @override
  State<PartnerProfileSheet> createState() => _PartnerProfileSheetState();
}

class _PartnerProfileSheetState extends State<PartnerProfileSheet> {
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final s = await widget.friendService.getFriendshipStatus(widget.partnerId);
    if (mounted) setState(() { _status = s; _loading = false; });
  }

  Future<void> _sendRequest() async {
    setState(() => _loading = true);
    try {
      await widget.friendService.sendRequest(widget.partnerId);
      if (mounted) setState(() { _status = 'pending'; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 40,
            backgroundColor: kPrimary,
            child: Text(
              widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.name,
            style: const TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (widget.bio != null && widget.bio!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary, fontSize: 14),
            ),
          ],
          const SizedBox(height: 24),
          _buildAction(),
        ],
      ),
    );
  }

  Widget _buildAction() {
    if (_loading) {
      return const SizedBox(
        height: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
      );
    }
    if (_status == 'accepted') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('Friends', style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    if (_status == 'pending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: const Text(
          'Request Sent',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextSecondary, fontSize: 15),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _sendRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text(
          'Add Friend',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
