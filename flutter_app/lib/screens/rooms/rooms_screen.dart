import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

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
          'Rooms',
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kPrimaryDeep, Color(0xFF1E3A5F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎙️ Practice Together',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a private room or join a public room to practice English with friends.',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'What would you like to do?',
              style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _RoomOptionCard(
              icon: Icons.add_circle_outline_rounded,
              title: 'Create Room',
              subtitle: 'Start a private or public room and invite friends with a code.',
              color: kPrimary,
              onTap: () => context.push('/rooms/create'),
            ),
            const SizedBox(height: 12),
            _RoomOptionCard(
              icon: Icons.vpn_key_rounded,
              title: 'Join with Code',
              subtitle: 'Enter a 6-character code to join a friend\'s private room.',
              color: const Color(0xFF7C3AED),
              onTap: () => context.push('/rooms/join'),
            ),
            const SizedBox(height: 12),
            _RoomOptionCard(
              icon: Icons.public_rounded,
              title: 'Public Rooms',
              subtitle: 'Browse open rooms and jump into an English conversation.',
              color: kAccent,
              onTap: () => context.push('/rooms/public'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoomOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: kPrimaryDeep.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: kTextMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
