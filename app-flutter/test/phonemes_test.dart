// ignore_for_file: avoid_print

import 'dart:io';

import 'package:english_with_movies/core/transcript.dart';
import 'package:english_with_movies/services/paths.dart';
import 'package:english_with_movies/services/phonemes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Runs the real sound analysis: synthetic speech -> phoneme worker + espeak-ng -> analysis.
///
/// - Mac: the Mac app's Python worker and installed model, espeak-ng from Homebrew.
/// - Windows CI: the bundled worker and espeak-ng (TOOLS_DIR); the model is downloaded
///   from the release by the app's own downloader (PHONEME_DOWNLOAD=1).
void main() {
  final env = Platform.environment;
  final temp = Directory.systemTemp.createTempSync('ewm_phonemes');
  final macApp = p.join(env['HOME'] ?? '', 'Library/Application Support/EnglishWithMovies');
  final download = env['PHONEME_DOWNLOAD'] == '1';

  AppPaths.tools = Directory(env['TOOLS_DIR'] ?? p.join(temp.path, 'no-bundled-tools'));
  AppPaths.root = download ? temp : Directory(macApp);
  if (!Platform.isWindows) {
    final python = p.join(macApp, 'phonemes', 'venv', 'bin', 'python');
    final worker = p.join(Directory.current.path, '..', 'Sources', 'EnglishWithMovies', 'Phonemes', 'worker.py');
    PhonemeRecognizer.workerCommand = File(python).existsSync() ? [python, p.normalize(worker)] : null;
  }

  tearDownAll(() => temp.deleteSync(recursive: true));

  // With TOOLS_DIR (the Windows build) the test always runs, so a missing piece fails it.
  final available = env['TOOLS_DIR'] != null || (PhonemeRecognizer.problem == null && PhonemeRecognizer.isModelInstalled);

  test('analyzes recorded speech sound by sound', () async {
    if (download) {
      var last = 0.0;
      await PhonemeRecognizer.downloadModel((value) => last = value);
      expect(last, closeTo(1, 0.001));
    }
    expect(PhonemeRecognizer.problem, isNull);
    expect(PhonemeRecognizer.isModelInstalled, isTrue);

    const sentence = 'I think this is a big ship.';
    final wav = p.join(temp.path, 'speech.wav');
    if (Platform.isWindows) {
      final speak = await Process.run('powershell', [
        '-NoProfile', '-Command',
        'Add-Type -AssemblyName System.Speech; '
            r'$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
            r'$f = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo 16000, ([System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen), ([System.Speech.AudioFormat.AudioChannel]::Mono); '
            '\$s.SetOutputToWaveFile("$wav", \$f); \$s.Speak("$sentence"); \$s.Dispose()',
      ]);
      expect(speak.exitCode, 0, reason: '${speak.stderr}');
    } else {
      final say = await Process.run('say', ['--file-format=WAVE', '--data-format=LEI16@16000', '-o', wav, sentence]);
      expect(say.exitCode, 0, reason: '${say.stderr}');
    }

    final words = sentence.split(' ').indexed.map((e) => TimedWord(e.$2, e.$1 * 0.3, e.$1 * 0.3 + 0.25)).toList();
    final analysis = await PhonemeRecognizer.analyze(wav, TranscriptLine(0, 0, 2.5, words)).timeout(const Duration(minutes: 3));
    expect(analysis, isNotNull);
    print('heard: ${analysis!.heard.join(' ')}');
    print('score: ${analysis.score.toStringAsFixed(2)}');
    for (final word in analysis.words) {
      print('${word.text}: ${word.sounds.map((s) => s.heard == null ? s.expected : '${s.expected}>${s.heard}').join(' ')}');
    }
    expect(analysis.words.length, 7);
    expect(analysis.words[1].sounds.first.expected, 'θ'); // "think" starts with th
    expect(analysis.heard.length, greaterThan(10));
    // Synthetic speech is clear; most sounds should match.
    expect(analysis.score, greaterThan(0.6));

    // A second request reuses the open worker.
    final again = await PhonemeRecognizer.analyze(wav, TranscriptLine(0, 0, 2.5, words)).timeout(const Duration(minutes: 1));
    expect(again!.heard, analysis.heard);
    PhonemeRecognizer.stopWorker();
  }, skip: available ? false : 'needs espeak-ng, the phoneme worker and the model', timeout: const Timeout(Duration(minutes: 10)));
}
