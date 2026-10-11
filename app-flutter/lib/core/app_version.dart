/// The version of this app; must match pubspec.yaml (checked by test/core_test.dart).
const appVersion = '1.2.0';

/// "v1.10.0" is newer than "1.9.2"; anything that is not a version is never newer.
bool isNewerVersion(String candidate, String current) {
  List<int>? numbers(String version) {
    final parts = version.trim().replaceFirst(RegExp('^[vV]'), '').split('.').map(int.tryParse).toList();
    return parts.contains(null) || parts.isEmpty ? null : parts.cast<int>();
  }

  final a = numbers(candidate), b = numbers(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Black bars in covers: the last "crop=W:H:X:Y" from ffmpeg's cropdetect, or null when there is
/// nothing worth cropping (the full frame, or a dark scene that would leave a small piece).
String? cropFromFfmpegOutput(String output, {int? width, int? height}) {
  final match = RegExp(r'crop=(\d+):(\d+):(\d+):(\d+)').allMatches(output).lastOrNull;
  if (match == null) return null;
  final values = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  if (values[0] <= 32 || values[1] <= 32) return null;
  if (values[1] < values[0] * 0.38) return null;
  if (width != null && height != null && values[0] >= width - 4 && values[1] >= height - 4) return null;
  return 'crop=${values.join(':')}';
}
