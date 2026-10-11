import 'common_words_data.dart';
import 'word_normalizer.dart';

final Set<String> _common = commonWordsData.split(' ').toSet();

/// True for a word outside the 5,000 most common ones (counting forms such as "running" -> "run").
/// Capitalized words in the middle of a sentence are taken as names and skipped.
bool isUncommonWord(String word, {bool atSentenceStart = false}) {
  final key = lookupKey(word);
  if (key.length < 3 || !RegExp(r"^[a-z']+$").hasMatch(key)) return false;
  final firstLetter = RegExp(r'\p{L}', unicode: true).firstMatch(word)?.group(0);
  if (!atSentenceStart && firstLetter != null && firstLetter != firstLetter.toLowerCase()) return false;
  return !lookupCandidates(word).any(_common.contains);
}
