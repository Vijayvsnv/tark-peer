import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

class CallService {
  RtcEngine? _engine;
  bool _isMicEnabled = true;
  bool _isSpeakerEnabled = false;
  bool _isInCall = false;

  bool get isMicEnabled => _isMicEnabled;
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool get isInCall => _isInCall;

  Future<void> joinCall({
    required String appId,
    required String channelName,
    required String token,
    required int uid,
    Function(int uid)? onUserJoined,
    Function(int uid)? onUserOffline,
    // true = partner speaking, false = silent
    Function(bool speaking)? onPartnerSpeaking,
    // Agora AudioRoute int values:
    //  0=Headset  1=Earpiece  2=HeadsetNoMic  3=Speakerphone
    //  4=Loudspeaker  5=BluetoothHeadset  -1=Default
    Function(int routing)? onAudioRoutingChanged,
  }) async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('[CallService] User joined: $remoteUid');
        onUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[CallService] User offline: $remoteUid reason: $reason');
        onUserOffline?.call(remoteUid);
      },
      onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
        // uid=0 in the list means local user; remote speakers have their actual uid
        final partnerSpeaking = speakers.any(
          (s) => (s.uid ?? 0) != 0 && (s.volume ?? 0) > 25,
        );
        onPartnerSpeaking?.call(partnerSpeaking);
      },
      onAudioRoutingChanged: (routing) {
        debugPrint('[CallService] Audio routing: $routing');
        onAudioRoutingChanged?.call(routing);
      },
    ));

    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.enableAudio();
    await _engine!.disableVideo();

    // Default to earpiece, not speakerphone
    await _engine!.setDefaultAudioRouteToSpeakerphone(false);

    // Fire volume callbacks every 200 ms so speaking indicator works
    await _engine!.enableAudioVolumeIndication(
      interval: 200,
      smooth: 3,
      reportVad: true,
    );

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );

    _isMicEnabled = true;
    _isSpeakerEnabled = false;
    _isInCall = true;
    debugPrint('[CallService] Joined channel=$channelName uid=$uid');
  }

  Future<void> leaveCall() async {
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.release();
      _engine = null;
    }
    _isInCall = false;
    debugPrint('[CallService] Left channel');
  }

  Future<void> toggleMic() async {
    _isMicEnabled = !_isMicEnabled;
    await _engine?.muteLocalAudioStream(!_isMicEnabled);
    debugPrint('[CallService] Mic: ${_isMicEnabled ? "on" : "muted"}');
  }

  Future<void> setSpeakerphone(bool enabled) async {
    _isSpeakerEnabled = enabled;
    await _engine?.setEnableSpeakerphone(enabled);
    debugPrint('[CallService] Speaker: $enabled');
  }

  // Directly mute/unmute without changing _isMicEnabled.
  // Used for external interruptions (phone calls) so user's preference is preserved.
  Future<void> setMicMuted(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
    debugPrint('[CallService] Mic force-muted=$muted');
  }
}
