import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/pronunciation.dart';
import '../core/review.dart';
import '../core/saved_words.dart';
import '../core/study_log.dart';
import '../core/transcript.dart';
import 'media_tools.dart';
import 'paths.dart';

Map<String, dynamic>? _readJson(File file) {
  try {
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic> : null;
  } catch (_) {
    return null;
  }
}

void _writeJson(File file, Object json) => file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));

/// Saved words (saved-words.json).
class SavedWordsStore extends ChangeNotifier {
  SavedWordsStore() {
    final json = _readJson(_file);
    list = json == null ? WordList() : WordList.fromJson(json);
  }

  late final WordList list;
  File get _file => AppPaths.file(AppPaths.root, 'saved-words.json');

  bool contains(String word) => list.contains(word);

  void add(SavedWord word) => _change(() => list.add(word));
  void remove(String word) => _change(() => list.remove(word));
  void grade(String word, ReviewGrade grade) => _change(() => list.grade(word, grade));

  /// Saves and redraws after a sync merged another device's words into [list].
  void saveAfterSync() => _change(() {});

  void _change(VoidCallback change) {
    change();
    _writeJson(_file, list.toJson());
    notifyListeners();
  }
}

/// Study time for the daily goal and the streak (study.json).
class StudyStore extends ChangeNotifier {
  StudyStore() {
    final json = _readJson(_file);
    log = json == null ? StudyLog() : StudyLog.fromJson(json);
    deviceId = (json?['deviceId'] as String?) ?? '${Platform.operatingSystem}-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }

  late final StudyLog log;

  /// Identifies this device in the sync file, so its time adds up with the other devices'.
  late final String deviceId;
  double _pending = 0;
  File get _file => AppPaths.file(AppPaths.root, 'study.json');

  int get goalMinutes => log.goalMinutes;
  set goalMinutes(int value) {
    log.goalMinutes = value;
    save();
  }

  int get todayMinutes => log.secondsOn(DateTime.now()) ~/ 60;

  /// Adds study time; published and saved every 15 seconds of study.
  void add(double seconds) {
    _pending += seconds;
    if (_pending >= 15) save();
  }

  void save() {
    if (_pending > 0) log.add(_pending, deviceId);
    _pending = 0;
    _writeJson(_file, {...log.toJson(), 'deviceId': deviceId});
    notifyListeners();
  }
}

/// Pronunciation history (practice-history.json).
class PracticeStore extends ChangeNotifier {
  PracticeStore() {
    final json = _readJson(_file);
    history = json == null ? PracticeHistory() : PracticeHistory.fromJson(json);
  }

  late final PracticeHistory history;
  File get _file => AppPaths.file(AppPaths.root, 'practice-history.json');

  PracticeRecord? record(TranscriptLine line, String? source) => history.record(line.text, source);

  void add(PronunciationResult result, TranscriptLine line, String? source) {
    history.add(PracticeAttempt.fromResult(result), sentence: line.text, source: source, lineStart: line.start);
    _writeJson(_file, history.toJson());
    notifyListeners();
  }

  void remove(String id) {
    history.records.remove(id);
    saveAfterSync();
  }

  /// Saves and redraws after a sync merged another device's attempts into [history].
  void saveAfterSync() {
    _writeJson(_file, history.toJson());
    notifyListeners();
  }
}

class LibraryItem {
  LibraryItem({
    required this.path,
    required this.isAudio,
    required this.isDownload,
    required this.size,
    required this.added,
    this.duration,
    this.position,
    this.lastOpened,
    required this.hasTranscript,
  });

  final String path;
  final bool isAudio, isDownload, hasTranscript;
  final int size;
  final DateTime added;
  final double? duration, position;
  final DateTime? lastOpened;

  String get title => cleanMediaTitle(path);

  double? get progress => position != null && duration != null && duration! > 0 ? (position! / duration!).clamp(0, 1) : null;
  bool get isInProgress => progress != null && progress! > 0.02 && progress! < 0.95;
}

/// The library: the downloads folder plus files opened before (library.json).
class LibraryStore extends ChangeNotifier {
  LibraryStore() {
    final json = _readJson(_file) ?? {};
    for (final entry in json.entries) {
      _records[entry.key] = Map<String, dynamic>.from(entry.value as Map);
    }
    refresh();
  }

  static const videoExtensions = {'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi'};
  static const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'opus'};

  final _records = <String, Map<String, dynamic>>{};
  final _thumbnailAttempts = <String>{};
  final thumbnails = <String, File>{};
  List<LibraryItem> items = [];
  DateTime _lastSave = DateTime(0);

  File get _file => AppPaths.file(AppPaths.root, 'library.json');

  static String _ext(String path) => p.extension(path).replaceFirst('.', '').toLowerCase();
  static bool isMedia(String path) => videoExtensions.contains(_ext(path)) || audioExtensions.contains(_ext(path));
  static bool isPartial(String path) =>
      path.endsWith('.part') || path.endsWith('.ytdl') || RegExp(r'\.f\d+\.[a-z0-9]+$').hasMatch(path);

  LibraryItem? get featured => items.firstOrNull;
  List<LibraryItem> get continueWatching => items.where((i) => i.isInProgress).toList();
  List<LibraryItem> get downloads => items.where((i) => i.isDownload).toList();
  List<LibraryItem> get videos => items.where((i) => !i.isAudio && !i.isDownload).toList();
  List<LibraryItem> get music => items.where((i) => i.isAudio).toList();
  int get downloadsSize => downloads.fold(0, (sum, i) => sum + i.size);

  void refresh() {
    final paths = <String>{
      ...AppPaths.downloads.listSync().whereType<File>().map((f) => f.path).where((path) => isMedia(path) && !isPartial(path)),
      ..._records.keys.where((path) => File(path).existsSync()),
    };
    items = paths.map(_makeItem).toList()
      ..sort((a, b) => (b.lastOpened ?? b.added).compareTo(a.lastOpened ?? a.added));
    for (final item in items) {
      _loadThumbnail(item);
    }
    notifyListeners();
  }

  void recordOpened(String path) {
    (_records[path] ??= {})['lastOpened'] = DateTime.now().toIso8601String();
    save();
    refresh();
  }

  void updatePosition(String path, double seconds, double? duration) {
    final record = _records[path] ??= {};
    record['position'] = seconds;
    if (duration != null && duration > 0) record['duration'] = duration;
    if (DateTime.now().difference(_lastSave).inSeconds > 10) save();
  }

  /// Removes a file opened from elsewhere from the library (the file is kept).
  void forget(LibraryItem item) {
    _records.remove(item.path);
    save();
    refresh();
  }

  /// Deletes a downloaded file with its transcripts and cover.
  void delete(LibraryItem item) {
    thumbnails.remove(item.path)?.deleteSync();
    TranscriptCache.deleteMedia(item.path);
    _records.remove(item.path);
    save();
    refresh();
  }

  void save() {
    _lastSave = DateTime.now();
    _writeJson(_file, _records);
  }

  LibraryItem _makeItem(String path) {
    final stat = File(path).statSync();
    final record = _records[path];
    return LibraryItem(
      path: path,
      isAudio: audioExtensions.contains(_ext(path)),
      isDownload: p.equals(p.dirname(path), AppPaths.downloads.path),
      size: stat.size,
      added: stat.changed,
      duration: (record?['duration'] as num?)?.toDouble(),
      position: (record?['position'] as num?)?.toDouble(),
      lastOpened: DateTime.tryParse(record?['lastOpened'] as String? ?? ''),
      hasTranscript: TranscriptCache.exists(path),
    );
  }

  /// Covers are a frame from 10% into the video, made with ffmpeg.
  void _loadThumbnail(LibraryItem item) {
    final file = AppPaths.file(AppPaths.thumbnails, '${TranscriptCache.key(item.path, 'cover')}.jpg');
    if (file.existsSync()) {
      thumbnails[item.path] = file;
      return;
    }
    if (item.isAudio || !_thumbnailAttempts.add(item.path)) return;
    () async {
      final tools = MediaTools();
      final duration = item.duration ?? await tools.duration(item.path);
      if (duration != null && item.duration == null) {
        (_records[item.path] ??= {})['duration'] = duration;
        save();
      }
      try {
        await tools.extractFrame(item.path, ((duration ?? 60) * 0.1).clamp(1, 120), file.path);
        thumbnails[item.path] = file;
      } catch (_) {}
      refresh();
    }();
  }
}
