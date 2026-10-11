import 'transcript.dart';

const _pairs = {'[': ']', '(': ')', '*': '*'};
final _musicSymbols = RegExp('[♪♫♬🎵🎶]');
final _hasAlphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// An opening "(" not closed within this many words is treated as normal text.
const _maxAnnotationWords = 12;

/// Removes descriptions of sounds such as "[Music]", "(background music playing)",
/// "*sighs*" and "♪", including ones glued to words ("out.[MUSIC").
/// Returns each kept word with its position in [words].
List<(int, TimedWord)> cleanSoundAnnotations(List<TimedWord> words) {
  String? closing;
  final result = <(int, TimedWord)>[];

  for (var index = 0; index < words.length; index++) {
    final characters = words[index].text.split('');
    final kept = StringBuffer();
    for (var offset = 0; offset < characters.length; offset++) {
      final character = characters[offset];
      if (closing != null) {
        if (character == closing) closing = null;
        continue;
      }
      final close = _pairs[character];
      // "*" only starts an annotation at the beginning of a word ("*sighs*", not "f*ck").
      if (close != null && (character != '*' || offset == 0) && _isClosed(close, offset, characters, index, words)) {
        closing = close;
        continue;
      }
      kept.write(character);
    }
    final text = kept.toString().replaceAll(_musicSymbols, '').trim();
    // Nothing but punctuation left (e.g. the "." after "[Music].").
    if (!_hasAlphanumeric.hasMatch(text)) continue;
    result.add((index, words[index].copyWith(text: text)));
  }
  return result;
}

bool _isClosed(String close, int offset, List<String> characters, int wordIndex, List<TimedWord> words) {
  if (characters.sublist(offset + 1).contains(close)) return true;
  return words.skip(wordIndex + 1).take(_maxAnnotationWords).any((w) => w.text.contains(close));
}

/// The same transcript without sound descriptions; lines left empty are removed.
Transcript removeSoundAnnotations(Transcript transcript) {
  final lineOfWord = <int>[];
  for (var i = 0; i < transcript.lines.length; i++) {
    lineOfWord.addAll(List.filled(transcript.lines[i].words.length, i));
  }
  final wordsByLine = List.generate(transcript.lines.length, (_) => <TimedWord>[]);
  final all = transcript.lines.expand((l) => l.words).toList();
  for (final (index, word) in cleanSoundAnnotations(all)) {
    wordsByLine[lineOfWord[index]].add(word);
  }
  final lines = <TranscriptLine>[];
  for (final words in wordsByLine) {
    if (words.isEmpty) continue;
    lines.add(TranscriptLine(lines.length, words.first.start, words.last.end, words));
  }
  return Transcript(lines);
}
