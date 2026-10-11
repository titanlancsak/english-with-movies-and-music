import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'log.dart';
import 'media_tools.dart';
import 'paths.dart';

/// Faster transcription on Windows computers with an NVIDIA graphics card: the CUDA build of
/// whisper.cpp (271 MB) is downloaded once, when the user turns it on. If it fails on this
/// computer, the app goes back to the processor build and remembers it.
class GpuWhisper extends ChangeNotifier {
  /// The same whisper.cpp version the app ships with (WHISPER_RELEASE in .github/workflows/windows.yml).
  static const _url = 'https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-bin-win-cuda-11.8.0-x64.zip';

  double? progress;
  String? error;

  Directory get _folder => Directory(p.join(AppPaths.root.path, 'whisper-gpu'));
  File get _failedMarker => AppPaths.file(AppPaths.root, 'whisper-gpu-failed.txt');

  /// An NVIDIA driver is installed (it ships nvidia-smi).
  static bool get hasNvidia {
    if (!Platform.isWindows) return false;
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return File(p.join(root, 'System32', 'nvidia-smi.exe')).existsSync() ||
        File(r'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe').existsSync();
  }

  /// whisper-cli.exe of the CUDA build, when installed.
  String? get executable {
    if (!_folder.existsSync()) return null;
    for (final entity in _folder.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path).toLowerCase() == 'whisper-cli.exe') return entity.path;
    }
    return null;
  }

  bool get installed => executable != null;
  bool get failed => _failedMarker.existsSync();

  /// Use the graphics card for this transcription?
  bool get usable => installed && !failed;

  Future<void> install() async {
    if (progress != null) return;
    progress = 0;
    error = null;
    notifyListeners();
    final zip = File(p.join(AppPaths.work.path, 'whisper-gpu.zip'));
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(_url))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw ToolException('Falha ao baixar (HTTP ${response.statusCode}).');
      final total = response.contentLength ?? 0;
      final sink = zip.openWrite();
      var received = 0;
      var shown = 0.0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          final value = total > 0 ? received / total : 0.0;
          if (value - shown >= 0.01) {
            shown = value;
            progress = value * 0.95;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) throw ToolException('O download foi interrompido. Tente de novo.');
      if (_folder.existsSync()) _folder.deleteSync(recursive: true);
      // Windows can unzip by itself; no extra library needed.
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command', 'Expand-Archive -Force -LiteralPath "${zip.path}" -DestinationPath "${_folder.path}"',
      ]);
      if (result.exitCode != 0 || !installed) throw ToolException('Não consegui extrair os arquivos: ${result.stderr}');
      if (_failedMarker.existsSync()) _failedMarker.deleteSync();
      log('Transcrição pela placa de vídeo instalada');
    } on TimeoutException {
      error = 'O download parou de responder. Verifique a internet e tente de novo.';
    } catch (e) {
      error = e.toString();
      log('Placa de vídeo: $e');
    } finally {
      client.close();
      if (zip.existsSync()) zip.deleteSync();
      progress = null;
      notifyListeners();
    }
  }

  /// The CUDA build did not work here (old driver, unsupported card…): use the processor from now on.
  void markFailed(Object reason) {
    log('Placa de vídeo falhou, voltando para o processador: $reason');
    _failedMarker.writeAsStringSync('$reason');
    notifyListeners();
  }

  void remove() {
    if (_folder.existsSync()) _folder.deleteSync(recursive: true);
    if (_failedMarker.existsSync()) _failedMarker.deleteSync();
    notifyListeners();
  }
}
