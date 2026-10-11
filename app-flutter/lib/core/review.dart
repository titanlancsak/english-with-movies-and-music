/// How well the user remembered a word in a review.
enum ReviewGrade {
  again('Errei'),
  hard('Difícil'),
  good('Bom'),
  easy('Fácil');

  const ReviewGrade(this.title);
  final String title;
}

/// Spaced-repetition state of a saved word (a simplified SM-2, the method used by Anki).
class ReviewState {
  ReviewState({
    this.interval = 0,
    this.ease = 2.5,
    this.repetitions = 0,
    this.lapses = 0,
    required this.due,
    this.lastReviewed,
  });

  /// Days until the next review.
  double interval;

  /// How fast the interval grows (starts at 2.5, never below 1.3).
  double ease;
  int repetitions;
  int lapses;
  DateTime due;
  DateTime? lastReviewed;

  /// Learned well: an interval of three weeks or more.
  bool get isMastered => interval >= 21;

  ReviewState copy() => ReviewState(
      interval: interval, ease: ease, repetitions: repetitions, lapses: lapses, due: due, lastReviewed: lastReviewed);

  Map<String, dynamic> toJson() => {
        'interval': interval,
        'ease': ease,
        'repetitions': repetitions,
        'lapses': lapses,
        'due': due.toIso8601String(),
        'lastReviewed': lastReviewed?.toIso8601String(),
      };

  factory ReviewState.fromJson(Map<String, dynamic> json) => ReviewState(
        interval: (json['interval'] as num).toDouble(),
        ease: (json['ease'] as num).toDouble(),
        repetitions: json['repetitions'] as int,
        lapses: json['lapses'] as int,
        due: DateTime.parse(json['due'] as String),
        lastReviewed: DateTime.tryParse(json['lastReviewed'] as String? ?? ''),
      );
}

/// A word answered "Errei" comes back in the same session, after a few minutes.
const relearnDelay = Duration(minutes: 10);

ReviewState nextReview(ReviewState? previous, ReviewGrade grade, DateTime now) {
  final state = previous?.copy() ?? ReviewState(due: now);
  state.lastReviewed = now;

  switch (grade) {
    case ReviewGrade.again:
      if (state.repetitions > 0) state.lapses++;
      state.repetitions = 0;
      state.interval = 0;
      state.ease = (state.ease - 0.2).clamp(1.3, double.infinity);
      state.due = now.add(relearnDelay);
      return state;
    case ReviewGrade.hard:
      state.interval = state.repetitions == 0 ? 1 : (state.interval * 1.2).clamp(1, double.infinity);
      state.ease = (state.ease - 0.15).clamp(1.3, double.infinity);
    case ReviewGrade.good:
      state.interval = switch (state.repetitions) {
        0 => 1,
        1 => 3,
        _ => (state.interval * state.ease).roundToDouble(),
      };
    case ReviewGrade.easy:
      state.interval = state.repetitions == 0 ? 4 : (state.interval * state.ease * 1.3).roundToDouble();
      state.ease += 0.15;
  }
  state.repetitions++;
  state.due = now.add(Duration(seconds: (state.interval * 86400).round()));
  return state;
}

/// "10 min", "1 dia", "3 dias", "2 meses": shown on the answer buttons.
String describeNextReview(ReviewState? state, ReviewGrade grade, DateTime now) {
  final seconds = nextReview(state, grade, now).due.difference(now).inSeconds;
  if (seconds < 3600) return '${(seconds / 60).round()} min';
  final days = (seconds / 86400).round();
  if (days < 31) return days == 1 ? '1 dia' : '$days dias';
  final months = (days / 30).round();
  return months == 1 ? '1 mês' : '$months meses';
}
