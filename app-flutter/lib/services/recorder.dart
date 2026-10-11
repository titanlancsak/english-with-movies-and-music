import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Records the microphone to a 16 kHz mono WAV (what Whisper expects) and stops by
/// itself after the user finishes speaking.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  final isRecording = ValueNotifier<bool>(false);

  /// Input level 0...1 for the meter.
  final level = ValueNotifier<double>(0);

  StreamSubscription<Amplitude>? _amplitude;
  DateTime _startedAt = DateTime.now();
  DateTime? _silenceSince;
  bool _heardSpeech = false;
  Duration _maxDuration = const Duration(seconds: 15);
  void Function(String path)? _onFinish;
  String? _path;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String path, {required Duration maxDuration, required void Function(String path) onFinish}) async {
    await stop(notify: false);
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    _path = path;
    _onFinish = onFinish;
    _maxDuration = maxDuration;
    _startedAt = DateTime.now();
    _heardSpeech = false;
    _silenceSince = null;
    isRecording.value = true;
    _amplitude = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(_tick);
  }

  /// Stops automatically: 1.2 s of silence after speaking, nothing said in 6 s, or the time limit.
  void _tick(Amplitude amplitude) {
    final power = amplitude.current; // dBFS, about -160...0
    level.value = ((power + 50) / 50).clamp(0, 1);
    final now = DateTime.now();
    if (power > -32) {
      _heardSpeech = true;
      _silenceSince = null;
    } else if (power < -40 && _heardSpeech) {
      _silenceSince ??= now;
    }
    final finishedSpeaking = _silenceSince != null && now.difference(_silenceSince!).inMilliseconds > 1200;
    final elapsed = now.difference(_startedAt);
    if (finishedSpeaking || (!_heardSpeech && elapsed.inSeconds > 6) || elapsed > _maxDuration) stop();
  }

  Future<void> stop({bool notify = true}) async {
    await _amplitude?.cancel();
    _amplitude = null;
    if (!isRecording.value) return;
    await _recorder.stop();
    isRecording.value = false;
    level.value = 0;
    final finish = _onFinish, path = _path;
    _onFinish = null;
    if (notify && finish != null && path != null) finish(path);
  }

  Future<void> dispose() async {
    await stop(notify: false);
    await _recorder.dispose();
  }
}
