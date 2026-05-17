import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Top-level callback required by flutter_foreground_task.
@pragma('vm:entry-point')
void callTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_CallTaskHandler());
}

class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Manages two things during an active call:
///   1. Foreground service — shows a persistent notification so Android never
///      kills audio when the screen locks or the user switches apps.
///   2. Audio focus listener — detects when a phone call comes in and fires
///      [onMuteChanged] so the caller can mute/unmute Agora accordingly.
class CallAudioManager {
  static const _audioFocusChannel = EventChannel('tark_peer/audio_focus');

  StreamSubscription? _focusSub;

  /// Called with `true` when audio focus is lost (phone call started).
  /// Called with `false` when audio focus returns (phone call ended).
  void Function(bool muted)? onMuteChanged;

  Future<void> start() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tark_peer_call',
        channelName: 'Tark Peer Call',
        channelDescription: 'Keeps your call active when the screen is off',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWifiLock: false,
        allowWakeLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Tark Peer',
      notificationText: 'Call in progress...',
      callback: callTaskCallback,
    );
    debugPrint('[CallAudioManager] Foreground service: $result');

    _focusSub = _audioFocusChannel.receiveBroadcastStream().listen(
      (event) {
        debugPrint('[CallAudioManager] Audio focus: $event');
        if (event == 'loss') onMuteChanged?.call(true);
        if (event == 'gain') onMuteChanged?.call(false);
      },
      onError: (e) => debugPrint('[CallAudioManager] Focus error: $e'),
    );
  }

  Future<void> stop() async {
    _focusSub?.cancel();
    _focusSub = null;
    await FlutterForegroundTask.stopService();
    debugPrint('[CallAudioManager] Stopped');
  }
}
