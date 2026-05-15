import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class CallService {
  RtcEngine? _engine;
  bool _isMicEnabled = true;
  bool _isInCall = false;

  bool get isMicEnabled => _isMicEnabled;
  bool get isInCall => _isInCall;

  Future<void> joinCall({
    required String appId,
    required String channelName,
    required String token,
    required int uid,
    Function(int uid)? onUserJoined,
    Function(int uid)? onUserOffline,
  }) async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (connection, remoteUid, elapsed) => onUserJoined?.call(remoteUid),
      onUserOffline: (connection, remoteUid, reason) => onUserOffline?.call(remoteUid),
    ));

    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.enableAudio();
    await _engine!.disableVideo();

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
    _isInCall = true;
  }

  Future<void> leaveCall() async {
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.release();
      _engine = null;
    }
    _isInCall = false;
  }

  Future<void> toggleMic() async {
    _isMicEnabled = !_isMicEnabled;
    await _engine?.muteLocalAudioStream(!_isMicEnabled);
  }
}
