import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/parsers.dart';
import '../core/phonemes.dart';
import '../core/pronunciation.dart';
import '../core/saved_words.dart';
import '../core/transcript.dart';
import 'gpu.dart';
import 'language.dart';
import 'log.dart';
import 'media_tools.dart';
import 'paths.dart';
import 'phonemes.dart';
import 'sound_setup.dart';
import 'stores.dart';
import 'sync_service.dart';
import 'updates.dart';

/// The single app state, created in main().
late final AppController app;

enum Status { idle, working, ready, failed }

/// The screens in the sidebar (bottom bar on a phone).
enum AppSection { library, player, savedWords, review, practice }

class AppController extends ChangeNotifier {
  AppController() {
    final settings = _settings;
    model = WhisperModel.values.firstWhere((m) => m.name == settings['model'], orElse: () => WhisperModel.base);
    showTranslation = settings['showTranslation'] as bool? ?? false;
    speed = (settings['speed'] as num?)?.toDouble() ?? 1;
    highlightUncommon = settings['highlightUncommon'] as bool? ?? true;
    unawaited(updates.check());
    // Creating the sync service starts it (when a folder is set); the shell shows its state.
    sync.addListener(notifyListeners);
    updates.addListener(notifyListeners);
    player.stream.position.listen(_onPosition);
    // A film takes a while to transcribe on a phone; the screen stays on meanwhile.
    if (Platform.isAndroid) {
      addListener(() {
        final working = status == Status.working;
        if (working != _keepingScreenOn) {
          _keepingScreenOn = working;
          WakelockPlus.toggle(enable: working).ignore();
        }
      });
    }
  }

  bool _keepingScreenOn = false;

  final library = LibraryStore();
  final savedWords = SavedWordsStore();
  final practice = PracticeStore();
  final dictionary = DictionaryService();
  final translator = Translator();
  final speaker = Speaker();
  final study = StudyStore();
  late final sync = SyncService(savedWords, practice, study);
  final updates = UpdateChecker();
  final gpu = GpuWhisper();
  final soundSetup = SoundSetup();

  final player = Player();
  late final video = VideoController(player);

  AppSection section = AppSection.library;
  String? mediaPath;
  Transcript? transcript;
  Status status = Status.idle;
  String message = '';
  double? progress;

  /// Line and word being spoken; separate notifiers so only the subtitles redraw.
  final activeLine = ValueNotifier<int?>(null);
  final activeWord = ValueNotifier<int?>(null);

  /// Whether the subtitles scroll with playback (off while the user scrolls them).
  final follow = ValueNotifier<bool>(true);

  /// Emits a line index when the subtitles must jump there (after the video jumps).
  final scrollRequests = StreamController<int>.broadcast();

  late WhisperModel model;
  late bool showTranslation;

  // MARK: Study tools

  /// Playback speed (0.5 to 1.25), kept between films.
  late double speed;

  /// Plays the current line again and again.
  bool loopLine = false;
  int? _loopIndex;

  /// Listening challenge: the subtitles stay hidden until a line is tapped.
  bool hideSubtitles = false;
  final revealedLines = <int>{};

  /// Underlines words outside the 5,000 most common ones.
  late bool highlightUncommon;

  /// Shadowing: listen to a line, repeat it, get the score, go to the next one.
  bool shadowing = false;

  bool showSearch = false;
  String searchQuery = '';
  int searchIndex = 0;

  /// Where the subtitles came from when they were not transcribed, e.g. "Legenda do YouTube".
  String? subtitleSource;

  MediaTools? _tools;
  double? _lastTime;
  double? _segmentEnd;
  VoidCallback? _segmentDone;
  DateTime _lastPositionSave = DateTime(0);

  bool get isAudio => mediaPath != null && LibraryStore.audioExtensions.contains(p.extension(mediaPath!).replaceFirst('.', '').toLowerCase());
  String? get sourceName => mediaPath == null ? null : cleanMediaTitle(mediaPath!);

  // MARK: - Settings

  File get _settingsFile => AppPaths.file(AppPaths.root, 'settings.json');

  Map<String, dynamic> get _settings {
    try {
      return jsonDecode(_settingsFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void _saveSettings() => _settingsFile.writeAsStringSync(jsonEncode(
      {'model': model.name, 'showTranslation': showTranslation, 'speed': speed, 'highlightUncommon': highlightUncommon}));

  void setSpeed(double value) {
    speed = value;
    player.setRate(value);
    _saveSettings();
    notifyListeners();
  }

  void setLoopLine(bool value) {
    loopLine = value;
    _loopIndex = value ? activeLine.value : null;
    notifyListeners();
  }

  void setHideSubtitles(bool value) {
    hideSubtitles = value;
    revealedLines.clear();
    notifyListeners();
  }

  void reveal(int line) {
    revealedLines.add(line);
    notifyListeners();
  }

  void setHighlightUncommon(bool value) {
    highlightUncommon = value;
    _saveSettings();
    notifyListeners();
  }

  // MARK: - Search

  List<int> get searchMatches => transcript?.lineIndicesMatching(searchQuery) ?? [];

  int? get currentSearchLine {
    final matches = searchMatches;
    return matches.isEmpty ? null : matches[searchIndex.clamp(0, matches.length - 1)];
  }

  void setShowSearch(bool value) {
    showSearch = value;
    if (!value) searchQuery = '';
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    searchIndex = 0;
    notifyListeners();
  }

  /// Goes to the next (1) or previous (-1) line containing the search text.
  void showSearchResult(int step) {
    final matches = searchMatches;
    final t = transcript;
    if (matches.isEmpty || t == null) return;
    searchIndex = ((searchIndex + step) % matches.length + matches.length) % matches.length;
    seek(t.lines[matches[searchIndex]].start);
    notifyListeners();
  }

  // MARK: - Shadowing

  /// The line to practice: the one being spoken, or the first.
  TranscriptLine? get currentLine {
    final t = transcript;
    if (t == null || t.lines.isEmpty) return null;
    return t.lines[activeLine.value ?? 0];
  }

  TranscriptLine? lineAfter(TranscriptLine line) => transcript?.lines.where((l) => l.start > line.start + 0.01).firstOrNull;

  /// Leaving the player pauses it; the film stays open under "Assistindo".
  void showSection(AppSection value) {
    if (value == AppSection.player && mediaPath == null) return;
    if (value != AppSection.player) player.pause();
    section = value;
    notifyListeners();
  }

  void setModel(WhisperModel value) {
    model = value;
    _saveSettings();
    notifyListeners();
  }

  void setShowTranslation(bool value) {
    showTranslation = value;
    _saveSettings();
    notifyListeners();
  }

  // MARK: - Opening

  Future<void> open(String path, {double? at}) async {
    if (p.extension(path).toLowerCase() == '.srt') return importSubtitles(path);
    section = AppSection.player;
    if (at != null && path == mediaPath) {
      notifyListeners();
      seek(at);
      await player.play();
      return;
    }
    savePosition();
    cancel();
    mediaPath = path;
    transcript = null;
    subtitleSource = null;
    revealedLines.clear();
    loopLine = false;
    searchQuery = '';
    activeLine.value = null;
    activeWord.value = null;
    _lastTime = null;
    library.recordOpened(path);
    notifyListeners();

    log('Abrindo $path');
    // Transcription starts right away; it must not wait for the player
    // (on Windows, media_kit's play() future may never complete).
    unawaited(_transcribe(path, skipCache: false));
    try {
      await player.open(Media(path), play: false);
      await player.setRate(speed);
      if (at != null && at > 0) {
        await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 10), onTimeout: () => Duration.zero);
        await player.seek(Duration(milliseconds: (at * 1000).round()));
      }
      unawaited(player.play());
    } catch (error) {
      log('Erro no player: $error');
    }
  }

  /// Back to the library.
  Future<void> closeMedia() async {
    savePosition();
    cancel();
    await player.stop();
    mediaPath = null;
    transcript = null;
    status = Status.idle;
    section = AppSection.library;
    library.refresh();
    notifyListeners();
  }

  void importSubtitles(String path) {
    final contents = File(path).readAsStringSync(encoding: const Utf8Codec(allowMalformed: true));
    transcript = parseSrt(contents);
    if (mediaPath != null) {
      final key = TranscriptCache.key(mediaPath!, model.fileName);
      TranscriptCache.save(transcript!, key);
      subtitleSource = 'Legenda importada (.srt)';
      AppPaths.file(AppPaths.transcripts, '$key.source').writeAsStringSync(subtitleSource!);
    }
    status = mediaPath == null ? Status.idle : Status.ready;
    notifyListeners();
  }

  Future<void> retranscribe() async {
    if (mediaPath == null) return;
    cancel();
    transcript = null;
    await _transcribe(mediaPath!, skipCache: true);
  }

  Future<void> download(String link) async {
    cancel();
    final tools = _tools = MediaTools();
    _setWorking('Baixando o vídeo…', 0);
    log('Baixando $link');
    try {
      final file = await tools.downloadVideo(link.trim(), AppPaths.downloads.path, progress: _setProgress);
      await open(file);
    } catch (error) {
      _report(error);
    }
  }

  void cancel() {
    _tools?.cancel();
    _tools = null;
    if (status == Status.working) {
      status = transcript == null ? Status.idle : Status.ready;
      notifyListeners();
    }
  }

  Future<void> _transcribe(String path, {required bool skipCache}) async {
    final String key;
    try {
      key = TranscriptCache.key(path, model.fileName);
    } catch (error) {
      _report(error);
      return;
    }
    final sourceMarker = AppPaths.file(AppPaths.transcripts, '$key.source');
    final cached = skipCache ? null : TranscriptCache.load(key);
    if (cached != null) {
      log('Transcrição em cache: ${cached.lines.length} falas');
      transcript = cached;
      subtitleSource = sourceMarker.existsSync() ? sourceMarker.readAsStringSync() : null;
      status = Status.ready;
      notifyListeners();
      return;
    }
    // Subtitles that came with the video (YouTube, or a .srt next to the film) are ready at once
    // and usually more accurate than a transcription. "Transcrever de novo" uses Whisper instead.
    final srt = skipCache ? null : siblingSubtitles(path);
    if (srt != null) {
      final parsed = parseSrt(File(srt).readAsStringSync(encoding: const Utf8Codec(allowMalformed: true)));
      if (parsed.lines.isNotEmpty) {
        log('Legenda ao lado do vídeo: ${parsed.lines.length} falas');
        TranscriptCache.save(parsed, key);
        transcript = parsed;
        subtitleSource = p.isWithin(AppPaths.downloads.path, path) && !Platform.isAndroid ? 'Legenda do YouTube' : 'Legenda do arquivo .srt';
        sourceMarker.writeAsStringSync(subtitleSource!);
        status = Status.ready;
        library.refresh();
        notifyListeners();
        return;
      }
    }
    if (sourceMarker.existsSync()) sourceMarker.deleteSync();
    final tools = _tools = MediaTools();
    final wav = AppPaths.file(AppPaths.work, '$key.wav').path;
    try {
      if (!model.isDownloaded) {
        _setWorking('Baixando o modelo de transcrição (só na primeira vez)…', 0);
        log('Baixando o modelo ${model.fileName}');
        await model.download(_setProgress);
      }
      _setWorking('Extraindo o áudio…', null);
      await tools.extractAudio(path, wav);
      Transcript? result;
      // A Windows computer with an NVIDIA card can transcribe on it (see gpu.dart); if that fails,
      // the processor takes over.
      final gpuExecutable = gpu.usable ? gpu.executable : null;
      if (gpuExecutable != null) {
        _setWorking('Transcrevendo as falas com a placa de vídeo…', 0);
        log('Transcrevendo com ${model.fileName} na placa de vídeo');
        try {
          result = await tools.transcribe(wav, model.file.path, progress: _setProgress, executable: gpuExecutable);
        } on CancelledException {
          rethrow;
        } catch (error) {
          gpu.markFailed(error);
        }
      }
      if (result == null) {
        _setWorking('Transcrevendo as falas…', 0);
        log('Transcrevendo com ${model.fileName}');
        result = await tools.transcribe(wav, model.file.path, progress: _setProgress);
      }
      log('Transcrição pronta: ${result.lines.length} falas');
      if (path != mediaPath) return;
      TranscriptCache.save(result, key);
      transcript = result;
      status = Status.ready;
      library.refresh();
      notifyListeners();
    } catch (error) {
      _report(error);
    } finally {
      final file = File(wav);
      if (file.existsSync()) file.deleteSync();
    }
  }

  static const _importingMessage = 'Copiando o arquivo para o app…';

  /// Phones: the file picker copies the chosen file before returning, which takes a while for a film.
  void showImporting(bool importing) {
    if (importing) {
      _setWorking(_importingMessage, null);
    } else if (status == Status.working && message == _importingMessage) {
      status = transcript == null ? Status.idle : Status.ready;
      notifyListeners();
    }
  }

  /// Phones: moves the picker's temporary copy into the library folder and returns the new path.
  /// Picking the same file again reuses the copy already in the library.
  Future<String> importIntoLibrary(String path) async {
    if (p.isWithin(AppPaths.downloads.path, path)) return path;
    final source = File(path);
    final target = File(p.join(AppPaths.downloads.path, p.basename(path)));
    if (target.existsSync() && target.lengthSync() == source.lengthSync()) {
      await source.delete();
      return target.path;
    }
    var destination = target.path;
    for (var i = 2; File(destination).existsSync(); i++) {
      destination = p.join(AppPaths.downloads.path, '${p.basenameWithoutExtension(path)} ($i)${p.extension(path)}');
    }
    try {
      await source.rename(destination);
    } on FileSystemException {
      await source.copy(destination);
      await source.delete();
    }
    log('Importado: $destination');
    return destination;
  }

  void _setWorking(String text, double? value) {
    status = Status.working;
    message = text;
    progress = value;
    notifyListeners();
  }

  void _setProgress(double value) {
    progress = value;
    notifyListeners();
  }

  void _report(Object error) {
    if (error is CancelledException) return;
    log('Erro: $error');
    status = Status.failed;
    message = error.toString();
    notifyListeners();
  }

  // MARK: - Playback

  void seek(double seconds) {
    player.seek(Duration(milliseconds: (seconds * 1000).round()));
    _jumpSubtitles(seconds);
  }

  void savePosition() {
    if (mediaPath == null) return;
    final position = player.state.position.inMilliseconds / 1000;
    final duration = player.state.duration.inMilliseconds / 1000;
    library.updatePosition(mediaPath!, position, duration > 0 ? duration : null);
    library.save();
  }

  /// Plays only this line, then pauses.
  /// Plays only this line, then pauses; [then] runs when it finished playing.
  void playSegment(TranscriptLine line, {VoidCallback? then}) {
    seek(line.start);
    _segmentEnd = line.end + 0.2;
    _segmentDone = then;
    player.play();
  }

  void _onPosition(Duration position) {
    final time = position.inMilliseconds / 1000;
    // A jump: the slider, the skip buttons, a click on a line… not normal playback.
    final last = _lastTime;
    // Study time for the daily goal: real seconds of playback.
    if (last != null && player.state.playing && time > last && time - last < 1) study.add((time - last) / speed);
    final jumped = last != null && (time - last).abs() > 1;
    if (jumped) _jumpSubtitles(time);
    _lastTime = time;

    if (_segmentEnd != null && time >= _segmentEnd!) {
      _segmentEnd = null;
      player.pause();
      final done = _segmentDone;
      _segmentDone = null;
      done?.call();
    }
    // Repeat the line: back to its start once it ends.
    final lines = transcript?.lines;
    if (loopLine && _segmentEnd == null && lines != null && lines.isNotEmpty) {
      if (jumped || _loopIndex == null) _loopIndex = transcript!.lineIndexAt(time) ?? _loopIndex;
      final index = _loopIndex;
      if (index != null && time > lines[index].end + 0.3) {
        seek(lines[index].start);
        return;
      }
    }
    if (mediaPath != null && DateTime.now().difference(_lastPositionSave).inSeconds >= 5) {
      _lastPositionSave = DateTime.now();
      final duration = player.state.duration.inMilliseconds / 1000;
      library.updatePosition(mediaPath!, time, duration > 0 ? duration : null);
    }

    final t = transcript;
    if (t == null) return;
    final line = t.lineIndexAt(time);
    activeLine.value = line;
    activeWord.value = line == null ? null : t.lines[line].wordIndexAt(time);
  }

  void _jumpSubtitles(double time) {
    follow.value = true;
    final line = transcript?.nearestLineIndex(time);
    if (line != null) scrollRequests.add(line);
  }

  // MARK: - Pronunciation

  /// Transcribes the user's recording (without telling Whisper the sentence) and scores it.
  Future<PronunciationResult> assess(String recording, TranscriptLine line) async {
    var modelFile = model.isDownloaded ? model.file : WhisperModel.values.where((m) => m.isDownloaded).firstOrNull?.file;
    if (modelFile == null) {
      await WhisperModel.base.download((_) {});
      modelFile = WhisperModel.base.file;
    }
    // Whatever the microphone recorded, both recognizers get 16 kHz mono 16-bit audio.
    final wav = p.join(AppPaths.work.path, '${p.basenameWithoutExtension(recording)}-16k.wav');
    await MediaTools().extractAudio(recording, wav);
    try {
      // The sound analysis is a bonus: if it fails, the word-level score still works.
      final sounds = soundSetup.isReady
          ? PhonemeRecognizer.analyze(wav, line).then<SoundAnalysis?>((analysis) => analysis, onError: (Object error) {
              log('Análise de sons falhou: $error');
              return null;
            })
          : Future<SoundAnalysis?>.value(null);
      final heard = await MediaTools().transcribe(wav, modelFile.path);
      return scorePronunciation(line, heard.lines.expand((l) => l.words).toList(), sounds: await sounds);
    } finally {
      File(wav).delete().ignore();
    }
  }
}
