import 'dart:io';

import 'package:english_with_movies/services/media_tools.dart';
import 'package:english_with_movies/services/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Runs the real tools through MediaTools. Skipped when ffmpeg is not installed
/// (e.g. on the CI machine before the tools are bundled).
void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('ewm_test');
    AppPaths.tools = Directory(p.join(temp.path, 'no-bundled-tools'));
    AppPaths.root = temp;
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  final hasFfmpeg = () {
    AppPaths.tools = Directory('/nonexistent');
    return MediaTools.locate('ffmpeg') != null && MediaTools.locate('ffprobe') != null;
  }();

  test('runs ffmpeg and ffprobe to completion', () async {
    final video = p.join(temp.path, 'tone.mp4');
    // A 3-second test video with a tone, made by ffmpeg itself.
    final made = await Process.run(MediaTools.locate('ffmpeg')!, [
      '-nostdin', '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=10',
      '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', video,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    final tools = MediaTools();
    final duration = await tools.duration(video).timeout(const Duration(seconds: 20));
    expect(duration, closeTo(3, 0.2));

    final wav = p.join(temp.path, 'tone.wav');
    await tools.extractAudio(video, wav).timeout(const Duration(seconds: 20));
    expect(File(wav).lengthSync(), greaterThan(16000 * 2 * 2)); // > 2 s of 16 kHz 16-bit audio

    final jpg = p.join(temp.path, 'cover.jpg');
    await tools.extractFrame(video, 1, jpg).timeout(const Duration(seconds: 20));
    expect(File(jpg).existsSync(), isTrue);
  }, skip: hasFfmpeg ? false : 'ffmpeg not installed');

  // On a Mac with whisper-cpp and the app's base model: real speech -> real transcript.
  final model = File(p.join(Platform.environment['HOME'] ?? '', 'Library/Application Support/EnglishWithMovies/models/ggml-base.en.bin'));
  final canTranscribe = hasFfmpeg && Platform.isMacOS && model.existsSync() && MediaTools.locate('whisper-cli') != null;

  test('transcribes speech with whisper.cpp', () async {
    final aiff = p.join(temp.path, 'speech.aiff'), wav = p.join(temp.path, 'speech.wav');
    await Process.run('say', ['-o', aiff, 'We need to leave the harbor before sunset.']);
    final tools = MediaTools();
    await tools.extractAudio(aiff, wav);
    final transcript = await tools.transcribe(wav, model.path).timeout(const Duration(seconds: 60));
    expect(transcript.lines.map((l) => l.text).join(' ').toLowerCase(), contains('harbor before sunset'));
    expect(transcript.lines.first.words.first.confidence, isNotNull);
  }, skip: canTranscribe ? false : 'needs macOS, whisper-cpp and the base model');

  test('reports a failing tool instead of hanging', () async {
    await expectLater(
      MediaTools().extractAudio(p.join(temp.path, 'missing.mp4'), p.join(temp.path, 'x.wav')).timeout(const Duration(seconds: 20)),
      throwsA(isA<ToolException>()),
    );
  }, skip: hasFfmpeg ? false : 'ffmpeg not installed');
}
