import 'review.dart';
import 'word_normalizer.dart';

/// A word the user saved to review later, with the sentence where it was found.
class SavedWord {
  SavedWord({
    required this.word,
    this.phonetic,
    this.partOfSpeech,
    this.definition,
    this.translation,
    this.context,
    this.sourcePath,
    this.sourceTime,
    DateTime? dateAdded,
    this.review,
  })  : key = lookupKey(word),
        dateAdded = dateAdded ?? DateTime.now();

  final String key;
  final String word;
  final String? phonetic;
  final String? partOfSpeech;
  final String? definition;
  final String? translation;
  final String? context;
  final String? sourcePath;
  final double? sourceTime;
  final DateTime dateAdded;
  ReviewState? review;

  /// File name without extension or a trailing video id such as " [R6MlUcmOul8]".
  String? get sourceName => sourcePath == null ? null : cleanMediaTitle(sourcePath!);

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'partOfSpeech': partOfSpeech,
        'definition': definition,
        'translation': translation,
        'context': context,
        'sourcePath': sourcePath,
        'sourceTime': sourceTime,
        'dateAdded': dateAdded.toIso8601String(),
        'review': review?.toJson(),
      };

  factory SavedWord.fromJson(Map<String, dynamic> json) => SavedWord(
        word: json['word'] as String,
        phonetic: json['phonetic'] as String?,
        partOfSpeech: json['partOfSpeech'] as String?,
        definition: json['definition'] as String?,
        translation: json['translation'] as String?,
        context: json['context'] as String?,
        sourcePath: json['sourcePath'] as String?,
        sourceTime: (json['sourceTime'] as num?)?.toDouble(),
        dateAdded: DateTime.tryParse(json['dateAdded'] as String? ?? ''),
        review: json['review'] == null ? null : ReviewState.fromJson(json['review'] as Map<String, dynamic>),
      );
}

/// "Tears of Steel - Blender VFX Open Movie [R6MlUcmOul8].mp4" -> "Tears of Steel - Blender VFX Open Movie"
/// Accepts both Windows (\) and Unix (/) separators, whatever system runs the code.
String cleanMediaTitle(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return base.replaceAll(RegExp(r'\s*\[[A-Za-z0-9_-]{6,}\]$'), '').replaceAll('｜', '|');
}

/// The saved words, newest first.
class WordList {
  WordList([List<SavedWord>? words]) : words = words ?? [];

  final List<SavedWord> words;

  bool contains(String word) {
    final key = lookupKey(word);
    return words.any((w) => w.key == key);
  }

  /// Adds the word at the top; saving it again replaces the old entry but keeps its review progress.
  void add(SavedWord word) {
    if (word.key.isEmpty) return;
    final existing = words.where((w) => w.key == word.key).firstOrNull;
    if (word.review == null && existing != null) word.review = existing.review;
    remove(word.key);
    words.insert(0, word);
  }

  void remove(String word) {
    final key = lookupKey(word);
    words.removeWhere((w) => w.key == key);
  }

  List<SavedWord> filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return words;
    return words
        .where((w) => [w.word, w.definition, w.translation, w.context].any((f) => (f ?? '').toLowerCase().contains(q)))
        .toList();
  }

  /// CSV for spreadsheets or flashcard apps such as Anki.
  String csv() {
    final header = ['word', 'portuguese', 'phonetic', 'part of speech', 'definition', 'sentence', 'source'];
    final rows = words.map((w) => [w.word, w.translation, w.phonetic, w.partOfSpeech, w.definition, w.context, w.sourceName]
        .map((f) => csvField(f ?? ''))
        .join(','));
    return '${[header.join(','), ...rows].join('\n')}\n';
  }

  // MARK: review

  /// Words to review now (never-reviewed words count as due), most overdue first.
  List<SavedWord> due([DateTime? now]) {
    final at = now ?? DateTime.now();
    final list = words.where((w) => !(w.review?.due.isAfter(at) ?? false)).toList();
    list.sort((a, b) => (a.review?.due ?? DateTime(0)).compareTo(b.review?.due ?? DateTime(0)));
    return list;
  }

  int masteredCount() => words.where((w) => w.review?.isMastered ?? false).length;

  DateTime? nextDueDate([DateTime? now]) {
    final at = now ?? DateTime.now();
    final dates = words.map((w) => w.review?.due).whereType<DateTime>().where((d) => d.isAfter(at)).toList()..sort();
    return dates.firstOrNull;
  }

  void grade(String word, ReviewGrade grade, [DateTime? now]) {
    final key = lookupKey(word);
    for (final w in words) {
      if (w.key == key) w.review = nextReview(w.review, grade, now ?? DateTime.now());
    }
  }

  Map<String, dynamic> toJson() => {'words': words.map((w) => w.toJson()).toList()};

  factory WordList.fromJson(Map<String, dynamic> json) =>
      WordList((json['words'] as List? ?? []).map((w) => SavedWord.fromJson(w as Map<String, dynamic>)).toList());
}

String csvField(String value) {
  if (!value.contains(RegExp(r'[,"\n\r]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
