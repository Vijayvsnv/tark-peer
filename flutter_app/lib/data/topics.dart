import 'package:flutter/material.dart';

class TopicLevel {
  final int level;
  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final List<String> topics;

  const TopicLevel({
    required this.level,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.topics,
  });
}

const List<TopicLevel> kTopicLevels = [
  // ── Level 1 — Icebreakers ──────────────────────────────────────────────
  TopicLevel(
    level: 1,
    title: 'Icebreakers',
    subtitle: 'Perfect for first-time conversations',
    emoji: '👋',
    color: Color(0xFF60A5FA),
    topics: [
      'What are you up to today?',
      'Tell me your name and city.',
      'How is your weekend going?',
      'What did you have for lunch?',
      'How is the weather there?',
      'What do you do in your free time?',
      'What kind of music do you enjoy?',
      'Tea or coffee — which do you prefer?',
      'Are you a morning person or a night owl?',
      'Who do you live with at home?',
      'Are you working or studying?',
      'How is today different from yesterday?',
      'Did anything special happen today?',
      'What were you doing before joining this call?',
      'Is this your first time trying this app?',
    ],
  ),

  // ── Level 2 — Small Talk ───────────────────────────────────────────────
  TopicLevel(
    level: 2,
    title: 'Small Talk',
    subtitle: 'Casual chit-chat topics',
    emoji: '💬',
    color: Color(0xFF34D399),
    topics: [
      'What movie or series have you watched recently?',
      'Do you follow cricket? Who is your favourite team?',
      'Where did you go for your last vacation?',
      'What was your favourite cartoon as a child?',
      'What is your favourite food dish?',
      'Which OTT platform do you use the most?',
      'Which social media app do you spend the most time on?',
      'What is a recent purchase you really liked?',
      'What does your typical Sunday look like?',
      'Do you prefer eating out or home-cooked food?',
      'Are you into reading books?',
      'What do you do to pass time in a traffic jam?',
      'Which song is on repeat for you right now?',
      'Which city do you most want to visit someday?',
      'Do you have a favourite café or coffee shop?',
    ],
  ),

  // ── Level 3 — Personal Stories ─────────────────────────────────────────
  TopicLevel(
    level: 3,
    title: 'Personal Stories',
    subtitle: 'Share your memories & moments',
    emoji: '🎭',
    color: Color(0xFFF59E0B),
    topics: [
      'What is your funniest childhood memory?',
      'What has been your most embarrassing moment?',
      'How did you meet your best friend?',
      'Share an achievement you are proud of.',
      'Who was your favourite teacher in school and why?',
      'What is the best gift you have ever received?',
      'When did you last laugh really hard?',
      'Tell me about a risk you took in life.',
      'Has a book or movie ever changed your life?',
      'What is your most memorable trip?',
      'Which was more fun — school or college?',
      'Share a funny story your family loves to tell about you.',
      'What is the toughest situation you have faced?',
      'What is a big decision you made recently?',
      'Describe a moment when you felt everything was going right.',
    ],
  ),

  // ── Level 4 — Deep Questions ───────────────────────────────────────────
  TopicLevel(
    level: 4,
    title: 'Deep Questions',
    subtitle: 'Real conversations, real thoughts',
    emoji: '🌊',
    color: Color(0xFF8B5CF6),
    topics: [
      'Where do you see yourself in five years?',
      'What is your biggest fear?',
      'What does success mean to you?',
      'What advice would you give your younger self?',
      'Is there something you regret and cannot let go of?',
      'What is something you have a strong opinion about?',
      'Describe your perfect day.',
      'Which habit do you most want to change?',
      'Has any belief of yours changed recently?',
      'Which is more important to you — being rich or being happy?',
      'How do you balance family and career?',
      'What is a dream you have not achieved yet?',
      'How do you define failure?',
      'What do you think the purpose of life is?',
      'How do you deal with loneliness?',
    ],
  ),

  // ── Level 5 — Fun Debates ──────────────────────────────────────────────
  TopicLevel(
    level: 5,
    title: 'Fun Debates',
    subtitle: 'Pick a side and argue!',
    emoji: '🔥',
    color: Color(0xFFEF4444),
    topics: [
      'Dosa vs Pizza — which wins?',
      'iPhone vs Android — which is better?',
      'Bollywood vs Hollywood?',
      'Cricket vs Football?',
      'Winter vs Summer — which do you prefer?',
      'Cats vs Dogs — which is the better pet?',
      'Tea vs Coffee — final answer?',
      'Books vs their movie adaptations?',
      'Online vs offline shopping?',
      'Village life vs city life?',
      'Mountains vs beach for a vacation?',
      'WhatsApp vs Instagram — which is more useful?',
      'Home-cooked food vs restaurant food?',
      'Marvel vs DC?',
      'Old songs vs new songs?',
    ],
  ),
];
