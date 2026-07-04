import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/match_filter.dart';

Future<MatchFilter?> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<MatchFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _gender;
  String? _ageRange;
  double? _minRating;
  double? _maxRating;

  static const _ageOptions = ['Any', '18-22', '22-30', '30-40', '40+'];
  static const _ratingOptions = [1.0, 2.0, 3.0, 4.0, 5.0];

  String _ratingLabel(double r) => '${r.toStringAsFixed(0)}★';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Find Your Partner',
            style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Set your preferences before searching',
            style: TextStyle(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // ── Gender (LOCKED) ─────────────────────────────────────────────────
          _LockedSection(
            label: 'Gender',
            onTap: () => _showLockedSnackbar(context),
            child: Row(
              children: [
                _genderChip('Male', Icons.male),
                const SizedBox(width: 10),
                _genderChip('Female', Icons.female),
                const SizedBox(width: 10),
                _genderChip('Any', Icons.people_outline),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Age Range (LOCKED) ───────────────────────────────────────────────
          _LockedSection(
            label: 'Age Range',
            onTap: () => _showLockedSnackbar(context),
            child: _DropdownField<String>(
              value: _ageRange ?? 'Any',
              items: _ageOptions,
              label: (v) => v,
              onChanged: (_) {},
            ),
          ),
          const SizedBox(height: 24),

          // ── Rating Range (LOCKED) ────────────────────────────────────────────
          _LockedSection(
            label: 'Rating Range',
            onTap: () => _showLockedSnackbar(context),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      _DropdownField<double?>(
                        value: null,
                        items: [null, ..._ratingOptions],
                        label: (v) => v == null ? 'Any' : _ratingLabel(v),
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      _DropdownField<double?>(
                        value: null,
                        items: [null, ..._ratingOptions],
                        label: (v) => v == null ? 'Any' : _ratingLabel(v),
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── Buttons ──────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _gender = null;
                      _ageRange = null;
                      _minRating = null;
                      _maxRating = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Reset', style: TextStyle(color: kTextSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    MatchFilter(
                      gender: _gender,
                      ageRange: _ageRange,
                      minRating: _minRating,
                      maxRating: _maxRating,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Start Searching', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _genderChip(String label, IconData icon) {
    final selected = (label == 'Any' && _gender == null) || _gender == label.toLowerCase();
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = label == 'Any' ? null : label.toLowerCase()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kPrimary : kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? kPrimary : kBorder),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? Colors.white : kTextSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : kTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showLockedSnackbar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Premium feature — coming soon!'),
        ],
      ),
      backgroundColor: const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ),
  );
}

class _LockedSection extends StatelessWidget {
  final String label;
  final Widget child;
  final VoidCallback onTap;

  const _LockedSection({
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.lock_outline_rounded, size: 14, color: kTextMuted),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Opacity(
                opacity: 0.4,
                child: AbsorbPointer(child: child),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) label;
  final void Function(T) onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kTextSecondary),
          style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
          dropdownColor: kBackground,
          items: items
              .map((e) => DropdownMenuItem<T>(value: e, child: Text(label(e))))
              .toList(),
          onChanged: (v) { if (v != null || T == Null || items.contains(null)) onChanged(v as T); },
        ),
      ),
    );
  }
}
