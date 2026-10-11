import 'dart:math';

import 'phonemes.dart';
import 'transcript.dart';

enum WordStatus { correct, unsure, wrong, missing }

class WordResult {
  const WordResult(this.text, this.status, [this.heard]);
  final String text;
  final WordStatus status;

  /// What the recognizer heard instead, when different.
  final String? heard;
}

/// The result of comparing what the user said with a subtitle line.
class PronunciationResult {
  const PronunciationResult({
    required this.words,
    required this.extraWords,
    required this.recognizedText,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.score,
    this.speedRatio,
    this.longPauses = 0,
    this.sounds,
  });

  final List<WordResult> words;
  final List<String> extraWords;
  final String recognizedText;
  final double accuracy, fluency, completeness;

  /// 0...100
  final int score;

  /// The user's duration divided by the character's (1 = same speed).
  final double? speedRatio;
  final int longPauses;

  /// Sound-by-sound analysis, when the phoneme recognizer is installed.
  final SoundAnalysis? sounds;

  /// Short advice in Portuguese.
  List<String> get tips {
    String clean(String w) => w.replaceAll(RegExp(r"^[^\p{L}\p{N}'’-]+|[^\p{L}\p{N}'’-]+$", unicode: true), '');
    if (words.isNotEmpty && words.every((w) => w.status == WordStatus.missing)) {
      return ['Não consegui entender a frase. Fale mais perto do microfone e um pouco mais alto.'];
    }
    final tips = <String>[];
    final wrong = words.where((w) => w.status == WordStatus.wrong).take(3);
    final missing = words.where((w) => w.status == WordStatus.missing).take(4);
    final unsure = words.where((w) => w.status == WordStatus.unsure).take(3);
    if (wrong.isNotEmpty) {
      tips.add('Treine: ${wrong.map((w) => '“${clean(w.text)}” (entendi “${w.heard ?? '?'}”)').join(', ')}.');
    }
    if (missing.isNotEmpty) tips.add('Faltou: ${missing.map((w) => '“${clean(w.text)}”').join(', ')}.');
    if (unsure.isNotEmpty) tips.add('Quase lá: ${unsure.map((w) => '“${clean(w.text)}”').join(', ')} saiu pouco claro.');
    final ratio = speedRatio;
    if (ratio != null && ratio > 1.4) {
      tips.add('Você falou mais devagar que o personagem. Tente um ritmo mais natural.');
    } else if (ratio != null && ratio < 0.6) {
      tips.add('Você falou mais rápido que o personagem. Fale com calma, articulando cada palavra.');
    }
    if (longPauses > 0) tips.add('Evite pausas longas no meio da frase.');
    if (tips.isEmpty) tips.add(score >= 90 ? 'Excelente! Pronúncia clara e ritmo natural.' : 'Muito bem! Continue praticando.');
    return tips;
  }
}

/// Scores a spoken attempt against a subtitle line, word by word.
/// Accuracy 60% (with recognizer confidence; with a sound analysis, half of it comes from the sounds),
/// fluency 25% (speed and pauses), completeness 15%.
PronunciationResult scorePronunciation(TranscriptLine target, List<TimedWord> spoken, {SoundAnalysis? sounds}) {
  final expected = target.words.where((w) => comparable(w.text).isNotEmpty).toList();
  final heard = spoken.where((w) => comparable(w.text).isNotEmpty).toList();
  final recognizedText = spoken.map((w) => w.text).join(' ');
  if (expected.isEmpty) {
    return PronunciationResult(
        words: const [], extraWords: const [], recognizedText: recognizedText,
        accuracy: 0, fluency: 0, completeness: 0, score: 0, sounds: sounds);
  }

  final results = <WordResult>[];
  final extras = <String>[];
  var credit = 0.0;
  for (final step in align(expected.map((w) => comparable(w.text)).toList(), heard.map((w) => comparable(w.text)).toList())) {
    switch (step) {
      case MatchStep(:final e, :final h, :final similarity):
        if (similarity == 1) {
          final confident = (heard[h].confidence ?? 1) >= 0.5;
          results.add(WordResult(expected[e].text, confident ? WordStatus.correct : WordStatus.unsure));
          credit += confident ? 1 : 0.7;
        } else if (similarity >= 0.75) {
          results.add(WordResult(expected[e].text, WordStatus.unsure, heard[h].text));
          credit += 0.5;
        } else {
          results.add(WordResult(expected[e].text, WordStatus.wrong, heard[h].text));
        }
      case MissingStep(:final e):
        results.add(WordResult(expected[e].text, WordStatus.missing));
      case ExtraStep(:final h):
        extras.add(heard[h].text);
    }
  }

  final count = expected.length.toDouble();
  final wordAccuracy = max(0.0, credit / count - 0.05 * extras.length);
  // Nothing recognized means nothing to credit, whatever the sounds say.
  final accuracy = sounds == null ? wordAccuracy : (heard.isEmpty ? 0.0 : 0.5 * wordAccuracy + 0.5 * sounds.score);
  final missing = results.where((r) => r.status == WordStatus.missing).length;
  final completeness = 1 - missing / count;

  double? speedRatio;
  var longPauses = 0;
  var fluency = 0.0;
  if (heard.isNotEmpty && completeness > 0) {
    // Compare with the time the character takes for the part that was said.
    final actorDuration = max((target.end - target.start) * completeness, 0.3);
    final ratio = max(heard.last.end - heard.first.start, 0.1) / actorDuration;
    speedRatio = ratio;
    final speedScore = ratio >= 0.6 && ratio <= 1.4
        ? 1.0
        : ratio < 0.6
            ? max(0.0, (ratio - 0.3) / 0.3)
            : max(0.0, 1 - (ratio - 1.4) / 1.2);
    for (var i = 1; i < heard.length; i++) {
      if (heard[i].start - heard[i - 1].end > 0.8) longPauses++;
    }
    final pauseScore = max(0.0, 1 - 0.2 * longPauses);
    // Speaking fluently only counts for words that were said correctly.
    fluency = (0.7 * speedScore + 0.3 * pauseScore) * accuracy;
  }

  final score = (100 * (0.6 * accuracy + 0.25 * fluency + 0.15 * completeness)).round().clamp(0, 100);
  return PronunciationResult(
    words: results, extraWords: extras, recognizedText: recognizedText,
    accuracy: accuracy, fluency: fluency, completeness: completeness,
    score: score, speedRatio: speedRatio, longPauses: longPauses, sounds: sounds,
  );
}

const _numberWords = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
];

/// Lowercase letters only; small numbers are spelled out ("4" -> "four").
String comparable(String word) {
  final lowered = word.toLowerCase().replaceAll('’', "'");
  final digits = lowered.replaceAll(RegExp(r'[^0-9]'), '');
  final alphanumeric = lowered.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  if (digits.isNotEmpty && digits.length == alphanumeric.length) {
    final number = int.parse(digits);
    if (number < _numberWords.length) return _numberWords[number];
  }
  return lowered.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
}

/// 1 for identical words, down to 0 for completely different ones.
double similarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      current[j] = [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(min);
    }
    previous = current;
  }
  return 1 - previous[b.length] / max(a.length, b.length);
}

sealed class AlignStep {}

class MatchStep extends AlignStep {
  MatchStep(this.e, this.h, this.similarity);
  final int e, h;
  final double similarity;
}

class MissingStep extends AlignStep {
  MissingStep(this.e);
  final int e;
}

class ExtraStep extends AlignStep {
  ExtraStep(this.h);
  final int h;
}

/// Aligns expected and heard words (edit distance), so one wrong word does not shift the rest.
List<AlignStep> align(List<String> expected, List<String> heard) {
  final n = expected.length, m = heard.length;
  final cost = List.generate(n + 1, (i) => List.generate(m + 1, (j) => i == 0 ? j.toDouble() : (j == 0 ? i.toDouble() : 0.0)));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final substitution = 1 - similarity(expected[i - 1], heard[j - 1]);
      cost[i][j] = [cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + substitution].reduce(min);
    }
  }
  final steps = <AlignStep>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0) {
      final similar = similarity(expected[i - 1], heard[j - 1]);
      if ((cost[i][j] - (cost[i - 1][j - 1] + 1 - similar)).abs() < 1e-9) {
        steps.add(MatchStep(i - 1, j - 1, similar));
        i--;
        j--;
        continue;
      }
    }
    if (i > 0 && (cost[i][j] - (cost[i - 1][j] + 1)).abs() < 1e-9) {
      steps.add(MissingStep(i - 1));
      i--;
    } else {
      steps.add(ExtraStep(j - 1));
      j--;
    }
  }
  return steps.reversed.toList();
}

// MARK: - History

class PracticeAttempt {
  PracticeAttempt({required this.date, required this.score, required this.recognizedText});

  factory PracticeAttempt.fromResult(PronunciationResult result) =>
      PracticeAttempt(date: DateTime.now(), score: result.score, recognizedText: result.recognizedText);

  final DateTime date;
  final int score;
  final String recognizedText;

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'score': score, 'recognizedText': recognizedText};

  factory PracticeAttempt.fromJson(Map<String, dynamic> json) => PracticeAttempt(
      date: DateTime.parse(json['date'] as String), score: json['score'] as int, recognizedText: json['recognizedText'] as String? ?? '');
}

/// All attempts for one sentence of one movie or song.
class PracticeRecord {
  PracticeRecord({required this.sentence, this.source, required this.lineStart, List<PracticeAttempt>? attempts})
      : attempts = attempts ?? [];

  final String sentence;
  final String? source;
  final double lineStart;

  /// Oldest first.
  final List<PracticeAttempt> attempts;

  String get id => practiceKey(sentence, source);
  int get best => attempts.isEmpty ? 0 : attempts.map((a) => a.score).reduce(max);
  PracticeAttempt? get last => attempts.isEmpty ? null : attempts.last;

  Map<String, dynamic> toJson() =>
      {'sentence': sentence, 'source': source, 'lineStart': lineStart, 'attempts': attempts.map((a) => a.toJson()).toList()};

  factory PracticeRecord.fromJson(Map<String, dynamic> json) => PracticeRecord(
        sentence: json['sentence'] as String,
        source: json['source'] as String?,
        lineStart: (json['lineStart'] as num).toDouble(),
        attempts: (json['attempts'] as List).map((a) => PracticeAttempt.fromJson(a as Map<String, dynamic>)).toList(),
      );
}

String practiceKey(String sentence, String? source) => '${source ?? ''}|${sentence.toLowerCase()}';

class PracticeHistory {
  final Map<String, PracticeRecord> records = {};

  PracticeRecord? record(String sentence, String? source) => records[practiceKey(sentence, source)];

  void add(PracticeAttempt attempt, {required String sentence, String? source, required double lineStart}) {
    records.putIfAbsent(practiceKey(sentence, source), () => PracticeRecord(sentence: sentence, source: source, lineStart: lineStart))
        .attempts
        .add(attempt);
  }

  List<PracticeRecord> get recent =>
      records.values.toList()..sort((a, b) => (b.last?.date ?? DateTime(0)).compareTo(a.last?.date ?? DateTime(0)));

  int get attemptCount => records.values.fold(0, (sum, r) => sum + r.attempts.length);

  /// Average of the latest score of each sentence.
  int? get averageScore {
    final latest = records.values.map((r) => r.last?.score).whereType<int>().toList();
    if (latest.isEmpty) return null;
    return (latest.reduce((a, b) => a + b) / latest.length).round();
  }

  Map<String, dynamic> toJson() => {'records': records.values.map((r) => r.toJson()).toList()};

  static PracticeHistory fromJson(Map<String, dynamic> json) {
    final history = PracticeHistory();
    for (final r in (json['records'] as List? ?? [])) {
      final record = PracticeRecord.fromJson(r as Map<String, dynamic>);
      history.records[record.id] = record;
    }
    return history;
  }
}
