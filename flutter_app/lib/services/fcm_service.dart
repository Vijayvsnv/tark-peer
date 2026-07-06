import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    // Request permission (Android 13+)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Save token to Supabase
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);

    // Token refresh hone par update karo
    _fcm.onTokenRefresh.listen(_saveToken);

    // Foreground notification handling
    FirebaseMessaging.onMessage.listen((message) {
      // App foreground me hai — in-app handle hota hai already
    });
  }

  Future<void> _saveToken(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
  }
}
