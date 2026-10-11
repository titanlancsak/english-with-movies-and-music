import 'dart:math';

/// Study time per day, for the daily goal and the streak ("5 dias seguidos").
/// Time is kept per device so it can be added up across the computer and the phone (see sync.dart).
class StudyLog {
  StudyLog({Map<String, Map<String, double>>? devices, this.goalMinutes = 10}) : devices = devices ?? {};

  /// Device id -> day ("2026-10-12") -> seconds.
  final Map<String, Map<String, double>> devices;
  int goalMinutes;

  /// Watching counts as it happens; each reviewed card and each pronunciation attempt adds a little.
  static const secondsPerReview = 10.0;
  static const secondsPerPractice = 30.0;

  void add(double seconds, String device, [DateTime? date]) {
    if (seconds <= 0) return;
    final days = devices.putIfAbsent(device, () => {});
    final key = dayKey(date ?? DateTime.now());
    days[key] = (days[key] ?? 0) + seconds;
  }

  double secondsOn(DateTime date) {
    final key = dayKey(date);
    return devices.values.fold(0.0, (sum, days) => sum + (days[key] ?? 0));
  }

  /// 0...1 of today's goal.
  double todayProgress([DateTime? now]) => min(1, secondsOn(now ?? DateTime.now()) / (max(goalMinutes, 1) * 60));

  /// Days in a row that reached the goal. Today counts once reached; until then the streak
  /// from yesterday is still alive.
  int streak([DateTime? now]) {
    final goal = max(goalMinutes, 1) * 60.0;
    var date = now ?? DateTime.now();
    if (secondsOn(date) < goal) date = DateTime(date.year, date.month, date.day - 1, 12);
    var count = 0;
    while (secondsOn(date) >= goal) {
      count++;
      date = DateTime(date.year, date.month, date.day - 1, 12);
    }
    return count;
  }

  /// Keeps the larger value of each device and day.
  void merge(StudyLog other) {
    other.devices.forEach((device, days) {
      final mine = devices.putIfAbsent(device, () => {});
      days.forEach((day, seconds) => mine[day] = max(mine[day] ?? 0, seconds));
    });
  }

  StudyLog copy() => StudyLog(devices: {for (final e in devices.entries) e.key: Map.of(e.value)}, goalMinutes: goalMinutes);

  /// "2026-10-12" in the local time zone.
  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'devices': devices, 'goalMinutes': goalMinutes};

  factory StudyLog.fromJson(Map<String, dynamic> json) => StudyLog(
        devices: {
          for (final e in (json['devices'] as Map? ?? {}).entries)
            e.key as String: {for (final d in (e.value as Map).entries) d.key as String: (d.value as num).toDouble()},
        },
        goalMinutes: json['goalMinutes'] as int? ?? 10,
      );
}
