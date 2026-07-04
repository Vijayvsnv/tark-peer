import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/topics.dart';
import '../../services/topic_progress_service.dart';

class TopicLevelScreen extends StatefulWidget {
  final TopicLevel level;

  const TopicLevelScreen({super.key, required this.level});

  @override
  State<TopicLevelScreen> createState() => _TopicLevelScreenState();
}

class _TopicLevelScreenState extends State<TopicLevelScreen> {
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
        final practicedCount = _progress.practicedCount(widget.level);
        final total = widget.level.topics.length;
        return Scaffold(
          backgroundColor: kBackground,
          appBar: AppBar(
            backgroundColor: kBackground,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: kTextPrimary),
              onPressed: () => context.pop(),
            ),
            title: Text(
              '${widget.level.emoji}  ${widget.level.title}',
              style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              _ProgressStrip(
                practiced: practicedCount,
                total: total,
                color: widget.level.color,
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: widget.level.topics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final topic = widget.level.topics[i];
                    final isDone = _progress.isPracticed(widget.level.level, i);
                    return _TopicTile(
                      index: i + 1,
                      topic: topic,
                      color: widget.level.color,
                      isDone: isDone,
                      onTap: () => _showTopicSheet(context, topic, i),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTopicSheet(BuildContext context, String topic, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _TopicSheet(
        topic: topic,
        color: widget.level.color,
        onUse: () async {
          Navigator.pop(context);
          await _progress.markPracticed(widget.level.level, index);
          if (mounted) context.go('/matching');
        },
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  final int practiced;
  final int total;
  final Color color;

  const _ProgressStrip({
    required this.practiced,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : practiced / total;
    final isComplete = practiced >= total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border(bottom: BorderSide(color: kBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$practiced / $total topics practiced',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isComplete) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle, color: kSuccess, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Level Complete!',
                  style: TextStyle(
                    color: kSuccess,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  final int index;
  final String topic;
  final Color color;
  final bool isDone;
  final VoidCallback onTap;

  const _TopicTile({
    required this.index,
    required this.topic,
    required this.color,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDone ? kSuccess.withOpacity(0.4) : kBorder),
            color: isDone ? kSuccess.withOpacity(0.05) : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isDone ? kSuccess : color).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: kSuccess, size: 18)
                      : Text(
                          '$index',
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  topic,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicSheet extends StatelessWidget {
  final String topic;
  final Color color;
  final VoidCallback onUse;

  const _TopicSheet({
    required this.topic,
    required this.color,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 22),
            const Text(
              'YOUR TOPIC',
              style: TextStyle(
                color: kTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              topic,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: topic));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Topic copied'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16, color: kTextSecondary),
                    label: const Text(
                      'Copy',
                      style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.mic, size: 18, color: Colors.white),
                    label: const Text(
                      'Use in Next Call',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
