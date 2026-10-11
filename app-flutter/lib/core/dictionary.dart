const maxExamples = 3;

class Sense {
  const Sense(this.partOfSpeech, this.definition);
  final String partOfSpeech;
  final String definition;
}

class DictionaryEntry {
  const DictionaryEntry({required this.word, this.phonetic, required this.senses, required this.examples});

  final String word;
  final String? phonetic;
  final List<Sense> senses;

  /// At most [maxExamples] example sentences.
  final List<String> examples;
}

/// Parses https://en.wiktionary.org/api/rest_v1/page/definition/{word}
DictionaryEntry? parseWiktionary(String word, Map<String, dynamic> json) {
  final english = json['en'] as List?;
  if (english == null) return null;
  final senses = <Sense>[];
  final examples = <String>[];

  for (final entry in english) {
    final partOfSpeech = ((entry as Map)['partOfSpeech'] as String? ?? '').toLowerCase();
    var perPart = 0;
    for (final definition in (entry['definitions'] as List? ?? [])) {
      final text = stripHtml(((definition as Map)['definition'] as String?) ?? '');
      // Skip empty senses and pure cross references like "Alternative form of …".
      if (text.isEmpty) continue;
      if (perPart < 2 && senses.length < 5) {
        senses.add(Sense(partOfSpeech, text));
        perPart++;
      }
      for (final example in (definition['examples'] as List? ?? [])) {
        final sentence = stripHtml(example as String);
        if (sentence.isNotEmpty && examples.length < maxExamples && !examples.contains(sentence)) {
          examples.add(sentence);
        }
      }
    }
  }
  if (senses.isEmpty) return null;
  return DictionaryEntry(word: word, senses: senses, examples: examples);
}

/// Parses https://api.dictionaryapi.dev/api/v2/entries/en/{word}
DictionaryEntry? parseDictionaryApi(List<dynamic> json) {
  if (json.isEmpty) return null;
  final first = json.first as Map;
  final senses = <Sense>[];
  final examples = <String>[];
  for (final entry in json) {
    for (final meaning in ((entry as Map)['meanings'] as List? ?? [])) {
      final definitions = ((meaning as Map)['definitions'] as List? ?? []);
      for (var i = 0; i < definitions.length; i++) {
        final definition = definitions[i] as Map;
        if (i < 2 && senses.length < 5) {
          senses.add(Sense(meaning['partOfSpeech'] as String? ?? '', definition['definition'] as String? ?? ''));
        }
        final example = definition['example'] as String?;
        if (example != null && examples.length < maxExamples && !examples.contains(example)) examples.add(example);
      }
    }
  }
  if (senses.isEmpty) return null;
  final phonetics = (first['phonetics'] as List? ?? []).map((p) => (p as Map)['text'] as String?).whereType<String>();
  return DictionaryEntry(
    word: first['word'] as String? ?? '',
    phonetic: first['phonetic'] as String? ?? (phonetics.isEmpty ? null : phonetics.first),
    senses: senses,
    examples: examples,
  );
}

/// Removes HTML tags (and the CSS Wiktionary embeds in <style>) and decodes the common entities.
String stripHtml(String html) => html
    .replaceAll(RegExp(r'<(style|script)\b[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
