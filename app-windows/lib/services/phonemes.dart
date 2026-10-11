import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/phonemes.dart';
import '../core/transcript.dart';
import 'log.dart';
import 'media_tools.dart';
import 'paths.dart';

/// Sound-by-sound pronunciation analysis.
///
/// - Expected sounds: espeak-ng converts each word of the sentence into phonemes.
/// - Heard sounds: a phoneme recognizer (wav2vec2, converted to int8 ONNX) runs in a worker
///   process that stays open, so the model is loaded only once. On Windows the worker ships
///   with the app (tools\phonemes); the model is downloaded once, when the user turns the analysis on.
class PhonemeRecognizer {
  /// The model files, published as assets of the "sound-model" release.
  static const modelFiles = {
    'model.onnx': (bytes: 317626961, sha256: '0431728c201f6b5714cc10f134e46db5cadde314beccc7b9cdbd402d0fe8e06c'),
    'vocab.json': (bytes: 4637, sha256: 'd732ab2456c0c017930001dc9af0b41b3b93d25b2eb9740bf9d925508d7d87d0'),
  };
  static const _baseUrl = 'https://github.com/titanlancsak/english-with-movies-and-music/releases/download/sound-model';

  static Directory get folder => Directory(p.join(AppPaths.root.path, 'phonemes'));

  /// The command that starts the worker (the folder with the model is added as the last argument).
  /// Tests point it at the Python worker of the Mac app.
  static List<String>? workerCommand = _defaultWorker();

  static List<String>? _defaultWorker() {
    final worker = MediaTools.locate('phonemes');
    return worker == null ? null : [worker];
  }

  static bool get isModelInstalled => modelFiles.entries.every((entry) {
        final file = File(p.join(folder.path, entry.key));
        return file.existsSync() && file.lengthSync() == entry.value.bytes;
      });

  /// What is missing for the analysis to run, or null when everything is in place.
  static String? get problem {
    if (workerCommand == null || MediaTools.locate('espeak-ng') == null) {
      return 'Os programas da análise por som não estão nesta cópia do app. Baixe a versão mais recente pela página de Releases.';
    }
    return null;
  }

  /// Downloads the model (about 320 MB) with progress 0...1 and checks each file's SHA-256.
  static Future<void> downloadModel(void Function(double) progress) async {
    folder.createSync(recursive: true);
    final total = modelFiles.values.fold(0, (sum, f) => sum + f.bytes);
    var done = 0;
    final client = http.Client();
    try {
      for (final MapEntry(key: name, value: info) in modelFiles.entries) {
        final target = File(p.join(folder.path, name));
        if (target.existsSync() && target.lengthSync() == info.bytes) {
          done += info.bytes;
          continue;
        }
        final partial = File('${target.path}.part');
        try {
          final request = http.Request('GET', Uri.parse('$_baseUrl/$name'))..headers['User-Agent'] = 'EnglishWithMovies/1.0';
          final response = await client.send(request).timeout(const Duration(seconds: 30));
          log('Modelo de sons ($name): HTTP ${response.statusCode}');
          if (response.statusCode != 200) throw ToolException('Falha ao baixar o modelo de sons (HTTP ${response.statusCode}).');
          final sink = partial.openWrite();
          final digest = _DigestSink();
          final hasher = sha256.startChunkedConversion(digest);
          var received = 0;
          try {
            await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
              sink.add(chunk);
              hasher.add(chunk);
              received += chunk.length;
              progress((done + received) / total);
            }
          } finally {
            await sink.close();
            hasher.close();
          }
          if (received != info.bytes || digest.value.toString() != info.sha256) {
            throw ToolException('O download do modelo de sons veio incompleto. Tente de novo.');
          }
          await partial.rename(target.path);
          done += info.bytes;
        } finally {
          if (partial.existsSync()) partial.deleteSync();
        }
      }
      log('Modelo de sons instalado');
    } on TimeoutException {
      throw ToolException('O download do modelo de sons parou de responder. Verifique a internet e tente de novo.');
    } finally {
      client.close();
    }
  }

  /// Closes the worker (it is started again on the next analysis).
  static void stopWorker() {
    _worker?.stop();
    _worker = null;
  }

  static _Worker? _worker;
  static Set<String> _vocabulary = {};

  /// Compares a 16 kHz mono WAV with the line, sound by sound.
  static Future<SoundAnalysis?> analyze(String wav, TranscriptLine line) async {
    final words = line.words.map((w) => w.text).where((w) => RegExp(r'\p{L}', unicode: true).hasMatch(w)).toList();
    final command = workerCommand;
    if (words.isEmpty || command == null || !isModelInstalled) return null;

    if (_worker == null) {
      _worker = await _Worker.start(command, folder.path);
      final vocab = jsonDecode(File(p.join(folder.path, 'vocab.json')).readAsStringSync()) as Map<String, dynamic>;
      _vocabulary = vocab.keys.toSet();
    }
    final heard = _worker!.phonemes(wav);
    final expected = await Future.wait(words.map((word) => expectedPhonemes(word, vocabulary: _vocabulary)));
    try {
      return PhonemeAnalyzer.analyze(words: words, expected: expected, heard: await heard);
    } on ToolException {
      // A worker that stopped is started again on the next attempt.
      stopWorker();
      rethrow;
    }
  }

  /// The sounds of one word, from espeak-ng (one call per word keeps each word's sounds separate).
  static Future<List<String>> expectedPhonemes(String word, {Set<String> vocabulary = const {}}) async {
    final espeak = MediaTools.locate('espeak-ng');
    if (espeak == null) throw ToolException('Não encontrei o programa "espeak-ng".');
    // The Windows build looks for its data next to the program.
    final data = Directory(p.join(p.dirname(espeak), 'espeak-ng-data'));
    final result = await Process.run(
      espeak,
      [if (data.existsSync()) '--path=${p.dirname(espeak)}', '-q', '-v', 'en-us', '--ipa', '--sep=_', word],
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
    );
    if (result.exitCode != 0) throw ToolException('espeak-ng falhou: ${result.stderr}');
    return PhonemeAnalyzer.phonemesFromEspeak(result.stdout as String, vocabulary: vocabulary);
  }
}

/// The worker process: reads one WAV path per line, answers one JSON line per request.
class _Worker {
  _Worker._(this._process, this._lines);

  final Process _process;
  final StreamIterator<String> _lines;
  Future<void> _queue = Future.value();

  static Future<_Worker> start(List<String> command, String folder) async {
    log('Abrindo o analisador de sons');
    final process = await Process.start(command.first, [...command.skip(1), folder]);
    process.stdin.encoding = utf8;
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) => log('sons: $line'));
    final lines = StreamIterator(process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()));
    final worker = _Worker._(process, lines);
    // The first line says the model finished loading.
    final ready = await lines.moveNext().timeout(const Duration(minutes: 2), onTimeout: () => false);
    if (!ready) {
      process.kill();
      throw ToolException('O analisador de sons não abriu.');
    }
    return worker;
  }

  /// Requests are answered one at a time, in order.
  Future<List<String>> phonemes(String wav) {
    final answer = _queue.then((_) => _request(wav));
    _queue = answer.then((_) {}, onError: (_) {});
    return answer;
  }

  Future<List<String>> _request(String wav) async {
    _process.stdin.writeln(wav);
    await _process.stdin.flush();
    final hasLine = await _lines.moveNext().timeout(const Duration(minutes: 2), onTimeout: () => false);
    if (!hasLine) throw ToolException('O analisador de sons parou de responder.');
    final response = jsonDecode(_lines.current) as Map<String, dynamic>;
    if (response['error'] != null) throw ToolException('Análise de sons: ${response['error']}');
    return (response['phonemes'] as List).cast<String>();
  }

  void stop() => _process.kill();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
