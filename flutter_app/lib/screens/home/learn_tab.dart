import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/topics.dart';
import '../../services/topic_progress_service.dart';

class LearnTab extends StatefulWidget {
  const LearnTab({super.key});

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  final _progress = TopicProgressService();

  @override
  void initState() {
    super.initState();
    _progress.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _progress.practiced,
      builder: (context, _, __) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const Text(
              'CONVERSATION LEVELS',
              style: TextStyle(
                color: kPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Complete each level to unlock the next',
              style: TextStyle(color: kTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < kTopicLevels.length; i++) ...[
              _LevelCard(
                level: kTopicLevels[i],
                unlocked: _progress.isLevelUnlocked(i),
                practiced: _progress.practicedCount(kTopicLevels[i]),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _LevelCard extends StatelessWidget {
  final TopicLevel level;
  final bool unlocked;
  final int practiced;

  const _LevelCard({
    required this.level,
    required this.unlocked,
    required this.practiced,
  });

  @override
  Widget build(BuildContext context) {
    final total = level.topics.length;
    final isComplete = practiced >= total;
    final baseColor = unlocked ? level.color : Colors.grey.shade400;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (!unlocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Complete Level ${level.level - 1} to unlock this'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          context.push('/learn/level', extra: level);
        },
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kBorder),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [baseColor.withOpacity(0.08), Colors.white],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: unlocked
                        ? Text(level.emoji, style: const TextStyle(fontSize: 30))
                        : Icon(Icons.lock, color: Colors.grey.shade600, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'LEVEL ${level.level}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          if (isComplete) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle, color: kSuccess, size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        level.title,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        level.subtitle,
                        style: const TextStyle(color: kTextSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      _ProgressBar(
                        practiced: practiced,
                        total: total,
                        color: baseColor,
                      ),
                    ],
                  ),
                ),
                Icon(
                  unlocked ? Icons.chevron_right : Icons.lock_outline,
                  color: kTextSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int practiced;
  final int total;
  final Color color;

  const _ProgressBar({
    required this.practiced,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : practiced / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$practiced / $total topics practiced',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
