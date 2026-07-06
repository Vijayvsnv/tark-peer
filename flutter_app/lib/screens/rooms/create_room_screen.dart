import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/room_models.dart';
import '../../services/room_service.dart';
import '../../widgets/custom_button.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _roomService = RoomService();
  final _nameCtrl = TextEditingController();
  String _type = 'private';
  int _maxMembers = 2;
  bool _loading = false;

  static const _freeSizes = [2, 4];
  static const _premiumSizes = [6, 8, 10];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room name cannot be empty'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final room = await _roomService.createRoom(
        name: name,
        type: _type,
        maxMembers: _maxMembers,
      );
      if (mounted) context.pushReplacement('/rooms/lobby', extra: room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Create Room',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Room Name
            const Text('Room Name', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              maxLength: 50,
              decoration: InputDecoration(
                hintText: 'e.g. Vijay\'s English Circle',
                hintStyle: const TextStyle(color: kTextMuted),
                filled: true,
                fillColor: kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 1.5),
                ),
                counterStyle: const TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 24),

            // Room Type
            const Text('Room Type', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              children: [
                _TypeChip(
                  label: '🔒 Private',
                  subtitle: 'Join via code only',
                  selected: _type == 'private',
                  onTap: () => setState(() => _type = 'private'),
                ),
                const SizedBox(width: 12),
                _TypeChip(
                  label: '🌐 Public',
                  subtitle: 'Listed in public rooms',
                  selected: _type == 'public',
                  onTap: () => setState(() => _type = 'public'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Room Size
            const Text('Room Size', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              '6, 8, 10 members — Premium (coming soon)',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._freeSizes.map((s) => _SizeChip(
                  size: s,
                  selected: _maxMembers == s,
                  locked: false,
                  onTap: () => setState(() => _maxMembers = s),
                )),
                ..._premiumSizes.map((s) => _SizeChip(
                  size: s,
                  selected: false,
                  locked: true,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Premium feature — coming soon!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                )),
              ],
            ),
            const SizedBox(height: 36),

            CustomButton(
              label: 'Create Room',
              isLoading: _loading,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? kPrimary.withOpacity(0.08) : kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kPrimary : kBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: selected ? kPrimary : kTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: kTextMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  final int size;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _SizeChip({
    required this.size,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: selected
              ? kPrimary
              : locked
                  ? kSurface
                  : kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? kPrimary : kBorder,
            width: selected ? 0 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$size',
                  style: TextStyle(
                    color: selected ? Colors.white : locked ? kTextMuted : kTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  size == 1 ? 'person' : 'people',
                  style: TextStyle(
                    color: selected ? Colors.white70 : kTextMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            if (locked)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.lock_rounded, size: 12, color: kTextMuted.withOpacity(0.7)),
              ),
          ],
        ),
      ),
    );
  }
}
