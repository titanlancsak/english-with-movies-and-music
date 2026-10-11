import 'dart:io';

import 'pronunciation.dart';
import 'review.dart';
import 'saved_words.dart';
import 'study_log.dart';

/// The file shared between devices (e.g. in a Google Drive, Dropbox or OneDrive folder):
/// saved words, pronunciation history and study time. The Mac version reads and writes the
/// same format (Sources/LinguaCore/Sync.swift); data/sync-example.json is an example both
/// test suites read.
class SyncDocument {
  SyncDocument({required this.words, required this.deletedWords, required this.practice, required this.study});

  factory SyncDocument.of(WordList words, PracticeHistory practice, StudyLog study) =>
      SyncDocument(words: words.words, deletedWords: words.deleted, practice: practice.recent, study: study);

  static const fileName = 'english-with-movies-sync.json';

  final List<SavedWord> words;
  final Map<String, DateTime> deletedWords;
  final List<PracticeRecord> practice;
  final StudyLog study;

  /// Merges another device's data into the local lists:
  /// - each word keeps its most recently changed copy; a deletion newer than the word removes it;
  /// - pronunciation attempts of both sides are kept (the same attempt is not counted twice);
  /// - study time keeps the larger value of each device and day (the local goal stays).
  static void merge(SyncDocument remote, {required WordList words, required PracticeHistory practice, required StudyLog study}) {
    final byKey = {for (final w in words.words) w.key: w};
    for (final word in remote.words) {
      final local = byKey[word.key];
      if (local != null && !word.changed.isAfter(local.changed)) continue;
      var incoming = word;
      // Keep this device's file path when the other device's path does not exist here.
      final path = word.sourcePath;
      if (local != null && path != null && !_exists(path)) incoming = _withPath(word, local.sourcePath);
      byKey[word.key] = incoming;
    }
    final deleted = Map.of(words.deleted);
    remote.deletedWords.forEach((key, date) {
      final known = deleted[key];
      if (known == null || date.isAfter(known)) deleted[key] = date;
    });
    deleted.forEach((key, date) {
      final word = byKey[key];
      if (word != null && !word.changed.isAfter(date)) byKey.remove(key);
    });
    words.words
      ..clear()
      ..addAll(byKey.values.toList()..sort((a, b) => b.dateAdded.compareTo(a.dateAdded)));
    words.deleted
      ..clear()
      ..addAll(deleted);

    for (final record in remote.practice) {
      final known = (practice.record(record.sentence, record.source)?.attempts ?? []).map(_attemptId).toSet();
      for (final attempt in record.attempts) {
        if (!known.contains(_attemptId(attempt))) {
          practice.add(attempt, sentence: record.sentence, source: record.source, lineStart: record.lineStart);
        }
      }
    }
    for (final record in practice.records.values) {
      record.attempts.sort((a, b) => a.date.compareTo(b.date));
    }

    study.merge(remote.study);
  }

  /// The same attempt on two devices: same second and score.
  static String _attemptId(PracticeAttempt attempt) => '${attempt.date.millisecondsSinceEpoch ~/ 1000}|${attempt.score}';

  static bool _exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static SavedWord _withPath(SavedWord word, String? path) => SavedWord(
        word: word.word,
        phonetic: word.phonetic,
        partOfSpeech: word.partOfSpeech,
        definition: word.definition,
        translation: word.translation,
        context: word.context,
        sourcePath: path,
        sourceTime: word.sourceTime,
        dateAdded: word.dateAdded,
        review: word.review,
      );

  // MARK: JSON

  static String _date(DateTime date) => date.toUtc().toIso8601String();

  /// Also accepts dates without milliseconds or without a time zone (taken as UTC).
  static DateTime? _parse(String? text) {
    if (text == null) return null;
    final date = DateTime.tryParse(text);
    if (date == null) return null;
    return date.isUtc || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(text) ? date : DateTime.tryParse('${text}Z');
  }

  Map<String, dynamic> toJson() => {
        'app': 'english-with-movies',
        'version': 1,
        'words': [
          for (final w in words)
            {
              'word': w.word,
              if (w.phonetic != null) 'phonetic': w.phonetic,
              if (w.partOfSpeech != null) 'partOfSpeech': w.partOfSpeech,
              if (w.definition != null) 'definition': w.definition,
              if (w.translation != null) 'translation': w.translation,
              if (w.context != null) 'context': w.context,
              if (w.sourcePath != null) 'sourcePath': w.sourcePath,
              if (w.sourceTime != null) 'sourceTime': w.sourceTime,
              'added': _date(w.dateAdded),
              if (w.review != null)
                'review': {
                  'interval': w.review!.interval,
                  'ease': w.review!.ease,
                  'repetitions': w.review!.repetitions,
                  'lapses': w.review!.lapses,
                  'due': _date(w.review!.due),
                  if (w.review!.lastReviewed != null) 'lastReviewed': _date(w.review!.lastReviewed!),
                },
            },
        ],
        'deletedWords': deletedWords.map((key, date) => MapEntry(key, _date(date))),
        'practice': [
          for (final r in practice)
            {
              'sentence': r.sentence,
              if (r.source != null) 'source': r.source,
              'lineStart': r.lineStart,
              'attempts': [
                for (final a in r.attempts) {'date': _date(a.date), 'score': a.score, 'recognizedText': a.recognizedText},
              ],
            },
        ],
        'study': {'devices': study.devices},
      };

  factory SyncDocument.fromJson(Map<String, dynamic> json) {
    final words = <SavedWord>[];
    for (final item in (json['words'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final review = item['review'] as Map<String, dynamic>?;
      words.add(SavedWord(
        word: item['word'] as String,
        phonetic: item['phonetic'] as String?,
        partOfSpeech: item['partOfSpeech'] as String?,
        definition: item['definition'] as String?,
        translation: item['translation'] as String?,
        context: item['context'] as String?,
        sourcePath: item['sourcePath'] as String?,
        sourceTime: (item['sourceTime'] as num?)?.toDouble(),
        dateAdded: _parse(item['added'] as String?) ?? DateTime.now(),
        review: review == null
            ? null
            : ReviewState(
                interval: (review['interval'] as num).toDouble(),
                ease: (review['ease'] as num).toDouble(),
                repetitions: review['repetitions'] as int,
                lapses: review['lapses'] as int,
                due: _parse(review['due'] as String?) ?? DateTime.now(),
                lastReviewed: _parse(review['lastReviewed'] as String?),
              ),
      ));
    }
    final practice = [
      for (final r in (json['practice'] as List? ?? []).cast<Map<String, dynamic>>())
        PracticeRecord(
          sentence: r['sentence'] as String,
          source: r['source'] as String?,
          lineStart: (r['lineStart'] as num).toDouble(),
          attempts: [
            for (final a in (r['attempts'] as List? ?? []).cast<Map<String, dynamic>>())
              if (_parse(a['date'] as String?) != null)
                PracticeAttempt(date: _parse(a['date'] as String?)!, score: a['score'] as int, recognizedText: a['recognizedText'] as String? ?? ''),
          ],
        ),
    ];
    final deleted = <String, DateTime>{};
    (json['deletedWords'] as Map? ?? {}).forEach((key, value) {
      final date = _parse(value as String?);
      if (date != null) deleted[key as String] = date;
    });
    return SyncDocument(
      words: words,
      deletedWords: deleted,
      practice: practice,
      study: StudyLog.fromJson((json['study'] as Map<String, dynamic>?) ?? {}),
    );
  }
}
