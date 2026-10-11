import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/parsers.dart';
import '../core/transcript.dart';
import 'paths.dart';

class ToolException implements Exception {
  ToolException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CancelledException implements Exception {}

/// Runs ffmpeg, ffprobe, whisper.cpp and yt-dlp.
/// On Windows they ship in the app's "tools" folder; elsewhere they are looked up in PATH.
class MediaTools {
  Process? _running;
  bool _cancelled = false;

  static String? locate(String name) {
    final exe = Platform.isWindows ? '$name.exe' : name;
    final candidates = [
      p.join(AppPaths.tools.path, exe),
      p.join(AppPaths.tools.path, 'whisper', exe),
      if (!Platform.isWindows) ...['/opt/homebrew/bin/$exe', '/usr/local/bin/$exe'],
      ...(Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':').map((dir) => p.join(dir, exe)),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Tools that are missing, e.g. ["ffmpeg"].
  static List<String> missingTools() =>
      ['ffmpeg', 'ffprobe', 'whisper-cli', 'yt-dlp'].where((tool) => locate(tool) == null).toList();

  void cancel() {
    _cancelled = true;
    _running?.kill();
  }

  /// Converts the media's audio to 16 kHz mono WAV, the format Whisper expects.
  Future<void> extractAudio(String media, String wav) =>
      _run('ffmpeg', ['-y', '-loglevel', 'error', '-i', media, '-vn', '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wav]);

  /// One video frame as JPEG, for library covers.
  Future<void> extractFrame(String media, double seconds, String output) => _run('ffmpeg', [
        '-y', '-loglevel', 'error', '-ss', seconds.toStringAsFixed(1), '-i', media,
        '-frames:v', '1', '-vf', 'scale=640:-2', '-q:v', '4', output,
      ]);

  /// Duration in seconds, or null.
  Future<double?> duration(String media) async {
    final output = StringBuffer();
    try {
      await _run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', media], onLine: output.writeln);
    } catch (_) {
      return null;
    }
    return double.tryParse(output.toString().trim());
  }

  /// Runs Whisper on a WAV file and returns the parsed transcript.
  Future<Transcript> transcribe(String wav, String model, {void Function(double)? progress}) async {
    final base = p.withoutExtension(wav);
    final threads = (Platform.numberOfProcessors - 2).clamp(2, 16);
    await _run('whisper-cli', [
      '-m', model, '-f', wav, '-l', 'en', '-t', '$threads', '-ojf', '-of', base, '-pp',
      '--suppress-nst', // no "[Music]" or "(applause)" tokens
    ], onLine: (line) {
      // "whisper_print_progress_callback: progress =  42%"
      final match = RegExp(r'progress =\s*(\d+)%').firstMatch(line);
      if (match != null) progress?.call(int.parse(match.group(1)!) / 100);
    });
    final json = File('$base.json');
    final transcript = parseWhisperJson(await json.readAsBytes());
    await json.delete().catchError((_) => json);
    return transcript;
  }

  /// Downloads a YouTube (or other yt-dlp supported) video as .mp4. Returns the file path.
  /// If YouTube refuses an old yt-dlp (HTTP 403), updates yt-dlp once and retries.
  Future<String> downloadVideo(String link, String folder, {void Function(double)? progress}) async {
    Future<String> attempt() async {
      String? file;
      await _run('yt-dlp', [
        '--no-playlist', '--newline', '--progress',
        '-S', 'res:1080,vcodec:h264,acodec:aac', // plays everywhere, up to 1080p
        '--merge-output-format', 'mp4',
        if (locate('ffmpeg') != null) ...['--ffmpeg-location', locate('ffmpeg')!],
        '-o', p.join(folder, '%(title).120B [%(id)s].%(ext)s'),
        '--print', 'after_move:FILE:%(filepath)s',
        link,
      ], onLine: (line) {
        if (line.startsWith('FILE:')) {
          file = line.substring(5).trim();
        } else if (line.startsWith('[download]')) {
          final match = RegExp(r'([\d.]+)%').firstMatch(line);
          if (match != null) progress?.call(double.parse(match.group(1)!) / 100);
        }
      });
      if (file == null || !File(file!).existsSync()) {
        throw ToolException('O download terminou, mas o arquivo não foi encontrado.');
      }
      return file!;
    }

    try {
      return await attempt();
    } on ToolException catch (error) {
      if (!error.message.contains('403')) rethrow;
      await _run('yt-dlp', ['-U']).catchError((_) {});
      return attempt();
    }
  }

  Future<void> _run(String tool, List<String> arguments, {void Function(String line)? onLine}) async {
    final executable = locate(tool);
    if (executable == null) {
      throw ToolException('Não encontrei o programa "$tool". Baixe o app novamente pela página de Releases.');
    }
    if (_cancelled) throw CancelledException();
    final process = await Process.start(executable, arguments);
    _running = process;
    final log = StringBuffer();
    StreamSubscription<String> listen(Stream<List<int>> stream) => stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          log.writeln(line);
          onLine?.call(line);
        });
    final out = listen(process.stdout), err = listen(process.stderr);
    final code = await process.exitCode;
    await out.asFuture<void>().catchError((_) {});
    await err.asFuture<void>().catchError((_) {});
    _running = null;
    if (_cancelled) throw CancelledException();
    if (code != 0) {
      final text = log.toString();
      throw ToolException('$tool falhou:\n${text.length > 600 ? text.substring(text.length - 600) : text}');
    }
  }
}

/// Whisper models (free, from https://huggingface.co/ggerganov/whisper.cpp).
enum WhisperModel {
  base('ggml-base.en.bin', 'Rápido (base, 148 MB)'),
  small('ggml-small.en.bin', 'Equilibrado (small, 488 MB)'),
  medium('ggml-medium.en-q5_0.bin', 'Preciso (medium, 539 MB)');

  const WhisperModel(this.fileName, this.title);
  final String fileName;
  final String title;

  File get file => AppPaths.file(AppPaths.models, fileName);
  bool get isDownloaded => file.existsSync();

  /// Downloads the model with progress (0...1).
  Future<void> download(void Function(double) progress) async {
    final url = Uri.parse('https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName');
    final response = await http.Client().send(http.Request('GET', url));
    if (response.statusCode != 200) throw ToolException('Falha ao baixar o modelo (${response.statusCode}).');
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) progress(received / total);
    }
    await sink.close();
    await partial.rename(file.path);
  }
}

/// Transcripts are saved so each file is transcribed only once.
class TranscriptCache {
  static String key(String media, String model) {
    final stat = File(media).statSync();
    final raw = '$media|${stat.size}|${stat.modified.millisecondsSinceEpoch ~/ 1000}|$model';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static File _file(String key) => AppPaths.file(AppPaths.transcripts, '$key.json');

  static Transcript? load(String key) {
    final file = _file(key);
    if (!file.existsSync()) return null;
    try {
      return Transcript.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void save(Transcript transcript, String key) => _file(key).writeAsStringSync(jsonEncode(transcript.toJson()));

  static bool exists(String media) => WhisperModel.values.any((m) => _file(key(media, m.fileName)).existsSync());

  /// Deletes a file together with its transcripts.
  static void deleteMedia(String media) {
    final file = File(media);
    if (!file.existsSync()) return;
    for (final model in WhisperModel.values) {
      final transcript = _file(key(media, model.fileName));
      if (transcript.existsSync()) transcript.deleteSync();
    }
    file.deleteSync();
  }
}
