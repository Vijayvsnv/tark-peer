import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/friend_service.dart';

class PartnerProfileSheet extends StatefulWidget {
  final String partnerId;
  final String name;
  final String? bio;
  final String? occupation;
  final String? sector;
  final String? country;
  final String? state;
  final FriendService friendService;

  const PartnerProfileSheet({
    super.key,
    required this.partnerId,
    required this.name,
    required this.bio,
    this.occupation,
    this.sector,
    this.country,
    this.state,
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
              color: kBorder,
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
          if (widget.state != null || widget.country != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, color: kTextSecondary, size: 14),
                const SizedBox(width: 4),
                Text(
                  [
                    if (widget.state != null) widget.state!,
                    if (widget.country != null) widget.country!,
                  ].join(', '),
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ],
          if ((widget.occupation != null && widget.occupation!.trim().isNotEmpty)
              || widget.sector != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (widget.occupation != null && widget.occupation!.trim().isNotEmpty)
                  widget.occupation!,
                if (widget.sector != null) widget.sector!,
              ].join(' · '),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
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
          color: kSuccess.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, color: kSuccess, size: 18),
            SizedBox(width: 8),
            Text('Friends', style: TextStyle(color: kSuccess, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    if (_status == 'pending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: const Text(
          'Request Sent',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextSecondary, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _sendRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Text(
          'Add Friend',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
