final _edges = RegExp(r'^[^\p{L}]+|[^\p{L}]+$', unicode: true);

/// Lowercases and strips surrounding punctuation: "“Don’t!”" -> "don't".
String lookupKey(String word) => word.replaceAll('’', "'").toLowerCase().replaceAll(_edges, '');

/// Base forms to try when the exact word is not in the dictionary,
/// e.g. "let's" -> "let", "running" -> "run", "studied" -> "study".
List<String> lookupCandidates(String word) {
  final key = lookupKey(word);
  if (key.isEmpty) return [];
  final result = <String>[key];

  void add(String value) {
    if (value.length >= 2 && !result.contains(value)) result.add(value);
  }

  String drop(String s, int n) => s.substring(0, s.length - n);

  for (final suffix in ["n't", "'s", "'re", "'ll", "'ve", "'d", "'m"]) {
    if (key.endsWith(suffix)) add(drop(key, suffix.length));
  }
  if (key.endsWith('ies') || key.endsWith('ied')) add('${drop(key, 3)}y');
  if (key.endsWith('ing')) {
    final stem = drop(key, 3);
    add(stem);
    add('${stem}e');
    if (stem.length >= 2 && stem[stem.length - 1] == stem[stem.length - 2]) add(drop(stem, 1));
  }
  if (key.endsWith('ed')) {
    final stem = drop(key, 2);
    add(stem);
    add(drop(key, 1));
    if (stem.length >= 2 && stem[stem.length - 1] == stem[stem.length - 2]) add(drop(stem, 1));
  }
  if (key.endsWith('es')) add(drop(key, 2));
  if (key.endsWith('s')) add(drop(key, 1));
  return result;
}
