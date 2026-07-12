import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/analytics_service.dart';
import '../services/report_service.dart';
import 'custom_button.dart';

const _kReasons = <String, String>{
  'abusive_language': 'Abusive language',
  'harassment': 'Harassment',
  'not_speaking_english': 'Not speaking English',
  'spam_or_scam': 'Spam or scam',
  'inappropriate_content': 'Inappropriate content',
  'other': 'Other',
};

class ReportSheet extends StatefulWidget {
  final String reportedId;
  final String reportedName;
  final String? roomId;

  const ReportSheet({
    super.key,
    required this.reportedId,
    required this.reportedName,
    this.roomId,
  });

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _reportService = ReportService();
  final _detailsCtrl = TextEditingController();
  String? _selectedReason;
  bool _loading = false;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    setState(() => _loading = true);
    final success = await _reportService.reportUser(
      reportedId: widget.reportedId,
      roomId: widget.roomId,
      reason: _selectedReason!,
      details: _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      AnalyticsService.instance.logReportSubmitted();
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit report. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Report User',
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Reporting ${widget.reportedName}',
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ..._kReasons.entries.map((entry) => _ReasonTile(
                  value: entry.key,
                  label: entry.value,
                  selected: _selectedReason == entry.key,
                  onTap: () => setState(() => _selectedReason = entry.key),
                )),
            const SizedBox(height: 14),
            TextField(
              controller: _detailsCtrl,
              maxLines: 3,
              maxLength: 300,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Additional details (optional)',
                hintStyle: TextStyle(color: kTextMuted),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
                counterStyle: TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(
              label: 'Submit Report',
              onPressed: _selectedReason == null ? null : _submit,
              isLoading: _loading,
              color: kDanger,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kPrimaryLight : kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kPrimary : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? kPrimary : kTextMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? kPrimary : kTextPrimary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
