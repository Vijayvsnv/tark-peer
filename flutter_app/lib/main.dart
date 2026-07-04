import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'data/topics.dart';
import 'models/match_event.dart';
import 'models/match_filter.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/profile/setup_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/matching/matching_screen.dart';
import 'screens/call/call_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/friends_screen.dart';
import 'screens/profile/friend_profile_screen.dart';
import 'screens/profile/call_history_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/games/vocabulary_quiz_screen.dart';
import 'screens/games/pronunciation_challenge_screen.dart';
import 'screens/games/dictation_screen.dart';
import 'screens/games/word_scramble_screen.dart';
import 'screens/games/fill_blanks_screen.dart';
import 'screens/home/topic_level_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const TarkPeerApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen()),
    GoRoute(
      path: '/friend/:id',
      builder: (_, state) => FriendProfileScreen(userId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/calls', builder: (_, __) => const CallHistoryScreen()),
    GoRoute(path: '/chat', builder: (_, __) => const ChatListScreen()),
    GoRoute(
      path: '/chat/:friendId',
      builder: (_, state) => ChatScreen(friendId: state.pathParameters['friendId']!),
    ),
    GoRoute(
      path: '/matching',
      builder: (_, state) => MatchingScreen(filter: state.extra as MatchFilter?),
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) {
        final event = state.extra as MatchEvent;
        return CallScreen(event: event);
      },
    ),
    GoRoute(
      path: '/games/vocab',
      builder: (_, state) {
        final level = int.tryParse(state.uri.queryParameters['level'] ?? '1') ?? 1;
        return VocabularyQuizScreen(level: level);
      },
    ),
    GoRoute(
      path: '/games/pronun',
      builder: (_, state) {
        final level = int.tryParse(state.uri.queryParameters['level'] ?? '1') ?? 1;
        return PronunciationChallengeScreen(level: level);
      },
    ),
    GoRoute(
      path: '/games/dict',
      builder: (_, state) {
        final level = int.tryParse(state.uri.queryParameters['level'] ?? '1') ?? 1;
        return DictationScreen(level: level);
      },
    ),
    GoRoute(
      path: '/games/scramble',
      builder: (_, state) {
        final level = int.tryParse(state.uri.queryParameters['level'] ?? '1') ?? 1;
        return WordScrambleScreen(level: level);
      },
    ),
    GoRoute(
      path: '/games/fill',
      builder: (_, state) {
        final level = int.tryParse(state.uri.queryParameters['level'] ?? '1') ?? 1;
        return FillBlanksScreen(level: level);
      },
    ),
    GoRoute(
      path: '/learn/level',
      builder: (_, state) => TopicLevelScreen(level: state.extra as TopicLevel),
    ),
  ],
);

class TarkPeerApp extends StatelessWidget {
  const TarkPeerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tark Peer',
      theme: appTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
