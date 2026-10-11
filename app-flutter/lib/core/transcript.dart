import 'word_normalizer.dart';

/// A single spoken word with its timing (in seconds).
class TimedWord {
  TimedWord(this.text, this.start, this.end, {this.confidence});

  String text;
  final double start;
  double end;

  /// How sure the speech recognizer was (0...1), when known.
  double? confidence;

  TimedWord copyWith({String? text}) => TimedWord(text ?? this.text, start, end, confidence: confidence);

  Map<String, dynamic> toJson() => {
        'text': text,
        'start': start,
        'end': end,
        if (confidence != null) 'confidence': confidence,
      };

  factory TimedWord.fromJson(Map<String, dynamic> json) => TimedWord(
        json['text'] as String,
        (json['start'] as num).toDouble(),
        (json['end'] as num).toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

/// One subtitle line (usually a sentence).
class TranscriptLine {
  TranscriptLine(this.id, this.start, this.end, this.words);

  final int id;
  final double start;
  final double end;
  final List<TimedWord> words;

  String get text => words.map((w) => w.text).join(' ');

  /// Index of the word being spoken at [time], or the last word already spoken.
  int? wordIndexAt(double time) {
    if (time < start) return null;
    int? result;
    for (var i = 0; i < words.length; i++) {
      if (words[i].start <= time) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'words': words.map((w) => w.toJson()).toList(),
      };

  factory TranscriptLine.fromJson(Map<String, dynamic> json) => TranscriptLine(
        json['id'] as int,
        (json['start'] as num).toDouble(),
        (json['end'] as num).toDouble(),
        (json['words'] as List).map((w) => TimedWord.fromJson(w as Map<String, dynamic>)).toList(),
      );
}

class Transcript {
  Transcript(this.lines);

  final List<TranscriptLine> lines;

  /// Lines whose text contains the query (ignoring case and accents), in order.
  List<int> lineIndicesMatching(String query) {
    final q = foldAccents(query.trim().toLowerCase());
    if (q.isEmpty) return [];
    return [for (var i = 0; i < lines.length; i++) if (foldAccents(lines[i].text.toLowerCase()).contains(q)) i];
  }

  /// Index of the line being spoken at [time] (binary search). Between two lines the
  /// previous one stays active for up to 2 seconds after it ends.
  int? lineIndexAt(double time) {
    var low = 0, high = lines.length - 1;
    int? found;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].start <= time) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (found == null) return null;
    return time <= lines[found].end + 2 ? found : null;
  }

  /// The line to show at [time]: the one being spoken, the last one before it,
  /// or the first line. Used to scroll after a jump.
  int? nearestLineIndex(double time) {
    if (lines.isEmpty) return null;
    final index = lines.lastIndexWhere((l) => l.start <= time);
    return index < 0 ? 0 : index;
  }

  /// Lines that contain [word] (case and punctuation insensitive).
  List<TranscriptLine> linesContaining(String word, {required int limit}) {
    final key = lookupKey(word);
    if (key.isEmpty) return [];
    return lines.where((l) => l.words.any((w) => lookupKey(w.text) == key)).take(limit).toList();
  }

  Map<String, dynamic> toJson() => {'lines': lines.map((l) => l.toJson()).toList()};

  factory Transcript.fromJson(Map<String, dynamic> json) =>
      Transcript((json['lines'] as List).map((l) => TranscriptLine.fromJson(l as Map<String, dynamic>)).toList());
}

/// Groups timed words into readable subtitle lines.
List<TranscriptLine> buildLines(List<TimedWord> words, {Set<int> segmentBreaks = const {}}) {
  final lines = <TranscriptLine>[];
  var current = <TimedWord>[];

  void flush() {
    if (current.isEmpty) return;
    lines.add(TranscriptLine(lines.length, current.first.start, current.last.end, current));
    current = [];
  }

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    current.add(word);
    final next = i + 1 < words.length ? words[i + 1] : null;
    final endsSentence = word.text.isNotEmpty && '.?!'.contains(word.text[word.text.length - 1]);
    final longPause = next == null || next.start - word.end > 1.0;
    final segmentEnd = segmentBreaks.contains(i) && current.length >= 6;
    if (endsSentence || longPause || segmentEnd || current.length >= 20) flush();
  }
  flush();
  return lines;
}

const _accents = {'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n'};

/// "café" -> "cafe", for searches that ignore accents.
String foldAccents(String text) => text.split('').map((c) => _accents[c] ?? c).join();
