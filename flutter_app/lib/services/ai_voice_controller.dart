import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum AiVoiceState { idle, listening, thinking, speaking, error }

typedef OnUserTurn = Future<void> Function(String text);
typedef OnUserSilent = Future<void> Function();

/// Turn-taking controller for the Shivani AI voice conversation.
///
/// Echo-loop prevention: STT is fully stopped before TTS plays. TTS completion
/// handler re-enters listening only after the audio output has finished.
class AiVoiceController {
  final OnUserTurn onUserTurn;
  final OnUserSilent onUserSilent;
  final void Function(String msg) onError;

  AiVoiceController({
    required this.onUserTurn,
    required this.onUserSilent,
    required this.onError,
  });

  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();

  final state = ValueNotifier<AiVoiceState>(AiVoiceState.idle);
  final partialText = ValueNotifier<String>('');

  bool _sttReady = false;
  bool _disposed = false;
  int _consecutiveEmpty = 0;
  Timer? _silenceTimer;
  static const _silenceThreshold = 2; // empty results before silent callback

  Future<void> init() async {
    // Init STT
    _sttReady = await _stt.initialize(
      onError: (e) {
        if (_disposed) return;
        if (e.errorMsg == 'error_speech_timeout' || e.errorMsg == 'error_no_match') {
          // Transient — restart listening
          _restartListening();
          return;
        }
        state.value = AiVoiceState.error;
        onError('Microphone error: ${e.errorMsg}');
      },
    );
    if (!_sttReady) {
      state.value = AiVoiceState.error;
      onError('Speech recognition not available on this device.');
      return;
    }

    // Init TTS
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(_onTtsComplete);
    _tts.setErrorHandler((msg) {
      if (_disposed) return;
      _onTtsComplete(); // recover by re-entering listening
    });
  }

  Future<void> startListening() async {
    if (_disposed || !_sttReady) return;
    if (state.value == AiVoiceState.listening) return;
    state.value = AiVoiceState.listening;
    partialText.value = '';
    await _stt.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      localeId: 'en_IN',
      onResult: _onSttResult,
    );
  }

  void _onSttResult(SpeechRecognitionResult result) {
    if (_disposed) return;
    partialText.value = result.recognizedWords;
    if (!result.finalResult) return;

    final text = result.recognizedWords.trim();
    if (text.isEmpty) {
      _consecutiveEmpty++;
      if (_consecutiveEmpty >= _silenceThreshold) {
        _consecutiveEmpty = 0;
        _startSilenceCallback();
      } else {
        _restartListening();
      }
      return;
    }

    _consecutiveEmpty = 0;
    _silenceTimer?.cancel();
    state.value = AiVoiceState.thinking;
    partialText.value = '';
    onUserTurn(text);
  }

  void _startSilenceCallback() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 20), () {
      if (_disposed || state.value != AiVoiceState.listening) return;
      onUserSilent();
    });
    _restartListening();
  }

  Future<void> _restartListening() async {
    if (_disposed || !_sttReady) return;
    await _stt.stop();
    await Future.delayed(const Duration(milliseconds: 100));
    if (_disposed || state.value == AiVoiceState.speaking || state.value == AiVoiceState.thinking) return;
    await startListening();
  }

  /// Speak Shivani's reply. STT is stopped first to prevent echo loop.
  Future<void> speak(String text) async {
    if (_disposed) return;
    // Stop STT before TTS — critical to prevent mic picking up speaker output
    await _stt.stop();
    await Future.delayed(const Duration(milliseconds: 150));
    if (_disposed) return;
    state.value = AiVoiceState.speaking;
    partialText.value = '';
    await _tts.speak(text);
  }

  void _onTtsComplete() {
    if (_disposed) return;
    if (state.value == AiVoiceState.speaking) {
      startListening();
    }
  }

  void pauseListening() {
    if (state.value == AiVoiceState.listening) {
      _stt.stop();
      state.value = AiVoiceState.idle;
    }
  }

  void resumeListening() {
    if (state.value == AiVoiceState.idle && _sttReady) {
      startListening();
    }
  }

  Future<void> stopAll() async {
    _disposed = true;
    _silenceTimer?.cancel();
    await _stt.stop();
    await _tts.stop();
    state.value = AiVoiceState.idle;
  }

  void dispose() {
    stopAll();
    state.dispose();
    partialText.dispose();
  }
}
