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

/// Learn tab levels — progression from beginner icebreakers to
/// playful debates. All levels are unlocked; user browses freely.
const List<TopicLevel> kTopicLevels = [
  // ── Level 1 — Icebreakers ──────────────────────────────────────────────
  TopicLevel(
    level: 1,
    title: 'Icebreakers',
    subtitle: 'Perfect for first-time conversations',
    emoji: '👋',
    color: Color(0xFF60A5FA),
    topics: [
      'Aaj kya kar rahe ho?',
      'Naam aur city batao',
      'Weekend kaisa jaa raha hai?',
      'Lunch mein kya khaya?',
      'Weather kaisa hai wahan?',
      'Free time mein kya karte ho?',
      'Kaunsa music sunna pasand hai?',
      'Chai ya coffee — kya prefer karte ho?',
      'Morning person ho ya night owl?',
      'Ghar pe kaun kaun hai?',
      'Working ho ya student?',
      'Kal se aaj kaise different hai?',
      'Aaj koi special baat hui?',
      'Kya karke abhi call join ki?',
      'Ye app pehli baar try kar rahe ho?',
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
      'Recently kaunsi movie ya series dekhi?',
      'Cricket dekhte ho? Favorite team?',
      'Last vacation kahan gaye the?',
      'Bachpan ka favorite cartoon?',
      'Favorite food dish kaunsi hai?',
      'OTT platform — Netflix, Prime ya Hotstar?',
      'Social media pe zyada kya use karte ho?',
      'Recent kuch purchase jo bahut pasand aayi?',
      'Sunday routine kya hoti hai?',
      'Restaurant ka khana ya ghar ka?',
      'Book padhne mein interest hai?',
      'Traffic jam mein kya karte ho time-pass?',
      'Favorite song jo repeat pe chal raha?',
      'Kaunsa city ghumna hai ek baar?',
      'Coffee shop favorite ya cafe?',
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
      'Bachpan ki funniest memory kaunsi hai?',
      'Sabse embarrassing moment kya raha?',
      'Best friend se pehli baar kaise mile the?',
      'Ek achievement jispe proud feel hota hai',
      'School ka sabse pasandida teacher kaun?',
      'Best gift jo kabhi mila?',
      'Recent kab bahut zyada hasa tha?',
      'Ek risk jo li thi zindagi mein',
      'Life-changing book ya movie?',
      'Sabse yaadgar trip kaunsa?',
      'School vs college — kaunsa fun tha?',
      'Ek kahani jo family mein tere naam se famous hai',
      'Sabse tough situation kaunsi face ki?',
      'Recent bada decision jo liya',
      'Ek pal jab tune sochha "life set hai"',
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
      '5 saal baad khudko kahan dekhte ho?',
      'Sabse badi fear kya hai?',
      'Success ka meaning kya hai tere liye?',
      'Young self ko ek advice — kya doge?',
      'Ek regret jo hamesha rehta hai?',
      'Kaunsi cheez pe strong opinion hai?',
      'Perfect day kaisa hoga tumhare liye?',
      'Kaunsi habit change karna chahte ho?',
      'Ek belief jo recently change hui?',
      'Rich hona ya happy hona — kya important?',
      'Family vs career — priority kya honi chahiye?',
      'Ek dream jo abhi tak complete nahi hua',
      'Failure ko define kaise karte ho?',
      'Life ka purpose kya lagta hai?',
      'Loneliness handle kaise karte ho?',
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
      'Dosa vs Pizza — kaun jeetega?',
      'iPhone vs Android — kya better hai?',
      'Bollywood vs Hollywood?',
      'Cricket vs Football?',
      'Winter vs Summer — kya pasand?',
      'Cats vs Dogs — best pet?',
      'Chai vs Coffee — final answer?',
      'Books vs Movie adaptations?',
      'Online vs Offline shopping?',
      'Village life vs City life?',
      'Mountains vs Beach vacation?',
      'WhatsApp vs Instagram — best app?',
      'Ghar ka khana vs Restaurant?',
      'Marvel vs DC?',
      'Old songs vs New songs?',
    ],
  ),
];
