import 'dart:math';

/// Sound-by-sound (phoneme) comparison between the expected sentence and what was said.
enum SoundStatus {
  /// The expected sound.
  correct,

  /// A close sound (e.g. a slightly different vowel).
  close,

  /// A different sound.
  wrong,

  /// Not pronounced.
  missing,
}

class Sound {
  const Sound(this.expected, this.status, [this.heard]);
  final String expected;
  final String? heard;
  final SoundStatus status;
}

class SoundWord {
  const SoundWord({required this.text, required this.sounds, required this.extra, required this.score});
  final String text;
  final List<Sound> sounds;

  /// Sounds added inside or right after the word (e.g. an "i" after a final consonant).
  final List<String> extra;

  /// 0...1
  final double score;
}

class SoundAnalysis {
  const SoundAnalysis({required this.words, required this.heard, required this.score});
  final List<SoundWord> words;

  /// Everything the phoneme recognizer heard.
  final List<String> heard;

  /// 0...1
  final double score;

  /// Advice in Portuguese for the most important sound problems (at most 3).
  List<String> get tips {
    final tips = <String>[];
    final seen = <String>{};
    void add(String key, String tip) {
      if (tips.length < 3 && seen.add(key)) tips.add(tip);
    }

    for (final word in words) {
      final name = word.text.replaceAll(RegExp(r"^[^\p{L}'’]+|[^\p{L}'’]+$", unicode: true), '');
      for (final sound in word.sounds.where((s) => s.status == SoundStatus.wrong || s.status == SoundStatus.missing)) {
        final tip = PhonemeTips.tip(sound.expected);
        if (tip != null) {
          add(sound.expected, '“$name”: $tip');
        } else if (sound.status == SoundStatus.missing) {
          add('missing-$name', '“$name”: faltou o som ${PhonemeTips.describe(sound.expected)}.');
        } else if (sound.heard != null) {
          add('${sound.expected}>${sound.heard}',
              '“$name”: você disse ${PhonemeTips.describe(sound.heard!)} no lugar de ${PhonemeTips.describe(sound.expected)}.');
        }
      }
      if (word.sounds.isNotEmpty && !PhonemeTips.isVowel(word.sounds.last.expected) && word.extra.any(PhonemeTips.isVowel)) {
        add('epenthesis', '“$name”: não acrescente um “i” no final. Termine a palavra na consoante.');
      }
    }
    return tips;
  }
}

class PhonemeAnalyzer {
  /// Splits espeak-ng output made with `--ipa --sep=_` (e.g. "θ_ˈɪ_ŋ_k") into phonemes,
  /// dropping stress marks. Unknown symbols are broken into known ones when possible.
  static List<String> phonemesFromEspeak(String text, {Set<String> vocabulary = const {}}) => text
      .replaceAll('ˈ', '')
      .replaceAll('ˌ', '')
      .split(RegExp(r'[_\s]+'))
      .where((s) => s.isNotEmpty)
      .expand((s) => _split(s, vocabulary))
      .toList();

  static List<String> _split(String symbol, Set<String> vocabulary) {
    if (vocabulary.isEmpty || vocabulary.contains(symbol)) return [symbol];
    final result = <String>[];
    var rest = symbol.runes.toList();
    while (rest.isNotEmpty) {
      var length = rest.length;
      while (length > 1 && !vocabulary.contains(String.fromCharCodes(rest.take(length)))) {
        length--;
      }
      result.add(String.fromCharCodes(rest.take(length)));
      rest = rest.sublist(length);
    }
    return result;
  }

  /// Compares expected phonemes (one list per word) with the heard phonemes.
  static SoundAnalysis analyze({required List<String> words, required List<List<String>> expected, required List<String> heard}) {
    final flat = [
      for (var w = 0; w < expected.length; w++)
        for (final symbol in expected[w]) (word: w, symbol: symbol),
    ];
    final results = [for (final _ in expected) <Sound>[]];
    final extras = [for (final _ in expected) <String>[]];
    var lastWord = 0;
    var extraCount = 0;

    for (final step in _align(flat.map((f) => f.symbol).toList(), heard)) {
      switch (step) {
        case _Pair(:final e, :final h):
          final s = similarity(flat[e].symbol, heard[h]);
          final status = s == 1 ? SoundStatus.correct : (s >= 0.6 ? SoundStatus.close : SoundStatus.wrong);
          results[flat[e].word].add(Sound(flat[e].symbol, status, status == SoundStatus.correct ? null : heard[h]));
          lastWord = flat[e].word;
        case _Missing(:final e):
          results[flat[e].word].add(Sound(flat[e].symbol, SoundStatus.missing));
          lastWord = flat[e].word;
        case _Extra(:final h):
          if (flat.isNotEmpty) extras[lastWord].add(heard[h]);
          extraCount++;
      }
    }

    var credit = 0.0;
    final analyzed = <SoundWord>[];
    for (var i = 0; i < words.length; i++) {
      final sounds = results[i];
      final wordCredit = sounds.fold(0.0, (sum, s) => sum + _credit(s.status));
      credit += wordCredit;
      final score = sounds.isEmpty ? 1.0 : max(0.0, wordCredit / sounds.length - 0.1 * extras[i].length);
      analyzed.add(SoundWord(text: words[i], sounds: sounds, extra: extras[i], score: score));
    }
    final overall = max(0.0, credit / max(1, flat.length) - 0.03 * extraCount);
    return SoundAnalysis(words: analyzed, heard: heard, score: min(1.0, overall));
  }

  static double _credit(SoundStatus status) => switch (status) {
        SoundStatus.correct => 1,
        SoundStatus.close => 0.6,
        SoundStatus.wrong || SoundStatus.missing => 0,
      };

  /// Sounds that are the same for scoring (length marks, reduced vowels, flap T).
  static const _equivalent = <Set<String>>[
    {'i', 'iː'}, {'u', 'uː'}, {'ɑ', 'ɑː'}, {'ɔ', 'ɔː'}, {'ɜ', 'ɜː'},
    {'ᵻ', 'ɪ', 'ə'}, {'ɚ', 'ɜː', 'əɹ'}, {'ɾ', 't', 'd'}, {'ɑːɹ', 'ɑɹ'}, {'ɔːɹ', 'ɔɹ', 'oːɹ'},
    {'r', 'ɹ'}, {'ɐ', 'ə'}, {'əl', 'l'},
  ];

  /// Sounds a learner can easily swap; close but not the same.
  static const _close = <Set<String>>[
    {'ɪ', 'i', 'iː', 'e'}, {'ʊ', 'u', 'uː'}, {'ʌ', 'ə', 'ɐ', 'a'}, {'æ', 'ɛ', 'a', 'e'},
    {'ɑː', 'ɑ', 'a', 'ɒ', 'ʌ'}, {'ɔː', 'ɔ', 'o', 'oʊ', 'ɒ'}, {'eɪ', 'e', 'ɛ'}, {'oʊ', 'o', 'ɔ'},
    {'aɪ', 'a'}, {'aʊ', 'a'}, {'ɚ', 'ɹ', 'ər'}, {'ɑːɹ', 'ɑː'}, {'ɔːɹ', 'ɔː'},
    {'s', 'z'}, {'f', 'v'}, {'tʃ', 'ʃ'}, {'dʒ', 'ʒ'}, {'n', 'ŋ'}, {'m', 'n'},
  ];

  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (_equivalent.any((set) => set.contains(a) && set.contains(b))) return 1;
    if (_close.any((set) => set.contains(a) && set.contains(b))) return 0.6;
    final aVowel = PhonemeTips.isVowel(a), bVowel = PhonemeTips.isVowel(b);
    if (aVowel && bVowel) return 0.3;
    if (!aVowel && !bVowel) return 0.2;
    return 0;
  }

  static List<_Step> _align(List<String> expected, List<String> heard) {
    final n = expected.length, m = heard.length;
    final cost = List.generate(n + 1, (i) => List.generate(m + 1, (j) => i == 0 ? j.toDouble() : (j == 0 ? i.toDouble() : 0.0)));
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final substitution = 1 - similarity(expected[i - 1], heard[j - 1]);
        cost[i][j] = [cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + substitution].reduce(min);
      }
    }
    final steps = <_Step>[];
    var i = n, j = m;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && cost[i][j] == cost[i - 1][j - 1] + 1 - similarity(expected[i - 1], heard[j - 1])) {
        steps.add(_Pair(i - 1, j - 1));
        i--;
        j--;
      } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
        steps.add(_Missing(i - 1));
        i--;
      } else {
        steps.add(_Extra(j - 1));
        j--;
      }
    }
    return steps.reversed.toList();
  }
}

sealed class _Step {}

class _Pair extends _Step {
  _Pair(this.e, this.h);
  final int e, h;
}

class _Missing extends _Step {
  _Missing(this.e);
  final int e;
}

class _Extra extends _Step {
  _Extra(this.h);
  final int h;
}

/// Names and advice (in Portuguese) for English sounds that are hard for Brazilians.
class PhonemeTips {
  static bool isVowel(String symbol) =>
      symbol.isNotEmpty && 'aeiouæɑɒɔəɚɛɜɪʊʌᵻɐøœyɨɯ'.runes.contains(symbol.runes.first);

  /// A friendly name, e.g. "th (think)".
  static String? name(String symbol) => _names[symbol];

  static String? tip(String symbol) => _tips[symbol];

  /// "o som “é (bed)” /ɛ/" when the sound has a friendly name, otherwise "/ɛ/".
  static String describe(String symbol) {
    final name = _names[symbol];
    return name == null ? '/$symbol/' : 'o som “$name” /$symbol/';
  }

  static const _names = {
    'θ': 'th (think)', 'ð': 'th (the)', 'ɹ': 'r (red)', 'h': 'h (house)', 'æ': 'a (cat)',
    'ɪ': 'i curto (ship)', 'iː': 'i longo (sheep)', 'i': 'i (happy)', 'ʊ': 'u curto (book)',
    'uː': 'u longo (food)', 'ʌ': 'a fechado (cup)', 'ə': 'vogal neutra (about)', 'ɑː': 'a aberto (father)',
    'ɑːɹ': 'ar (car)', 'ɔː': 'ó (thought)', 'ɔːɹ': 'or (more)', 'ɚ': 'er (teacher)', 'ɜː': 'er (bird)',
    'eɪ': 'ei (say)', 'oʊ': 'ou (go)', 'aɪ': 'ai (my)', 'aʊ': 'au (now)', 'ɔɪ': 'ói (boy)',
    'ŋ': 'ng (sing)', 'w': 'w (we)', 'v': 'v (very)', 'dʒ': 'dj (job)', 'tʃ': 'tch (chair)',
    'ʃ': 'sh (she)', 'ʒ': 'j (vision)', 'z': 'z (zoo)', 's': 's (see)', 't': 't (top)', 'd': 'd (dog)',
    'ɾ': 't/d rápido (water)', 'l': 'l (love)', 'ɛ': 'é (bed)', 'ᵻ': 'i fraco (wanted)',
  };

  static const _tips = {
    'θ': 'o “th” de think: ponha a ponta da língua entre os dentes e sopre, sem vibrar. Não é /t/, /f/ nem /s/.',
    'ð': 'o “th” de the: língua entre os dentes, vibrando a garganta. Não é /d/ nem /z/.',
    'ɹ': 'o R americano (red): curve a língua para trás sem encostar no céu da boca. Não é o R de “carro” nem o de “caro”.',
    'ɚ': 'o “er” de teacher: vogal com a língua curvada para trás, como o R americano.',
    'ɜː': 'o “er” de bird: vogal longa com a língua curvada para trás.',
    'æ': 'o “a” de cat: abra bem a boca, um som entre “é” e “á”.',
    'ɪ': 'o “i” curto de ship: mais curto e relaxado que o “i” de sheep.',
    'iː': 'o “i” longo de sheep: sorria e prolongue o “i”.',
    'ʊ': 'o “u” curto de book: mais curto e relaxado que o “u” de food.',
    'uː': 'o “u” longo de food: lábios arredondados, prolongue o “u”.',
    'ʌ': 'o “a” de cup: um “a” curto, com a boca pouco aberta.',
    'ɑː': 'o “a” de father: “a” bem aberto e longo, no fundo da boca.',
    'ɑːɹ': 'o “ar” de car: “a” aberto seguido do R americano.',
    'ɔːɹ': 'o “or” de more: “ó” seguido do R americano.',
    'ŋ': 'o “ng” de sing: som nasal no fundo da boca, sem pronunciar um “g” no final.',
    'w': 'o “w” de we: lábios arredondados como um “u” rápido. Não é /v/.',
    'v': 'o “v” de very: dentes de cima no lábio de baixo, vibrando. Não é /w/ nem /b/.',
    'h': 'o “h” de house: solte o ar suavemente, como um “r” de “rato” bem leve. Não deixe mudo.',
    'eɪ': 'o “ei” de say: deslize do “e” para o “i”.',
    'oʊ': 'o “ou” de go: deslize do “o” para o “u”, com os lábios arredondando.',
    'z': 'o “z” de zoo: vibre a garganta, como um zumbido.',
  };
}
