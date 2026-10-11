import 'dart:convert';

import 'package:english_with_movies/core/dictionary.dart';
import 'package:english_with_movies/core/parsers.dart';
import 'package:english_with_movies/core/pronunciation.dart';
import 'package:english_with_movies/core/review.dart';
import 'package:english_with_movies/core/saved_words.dart';
import 'package:english_with_movies/core/sound_annotations.dart';
import 'package:english_with_movies/core/transcript.dart';
import 'package:english_with_movies/core/word_normalizer.dart';
import 'package:test/test.dart';

String token(String text, int from, int to, [double p = 0.9]) =>
    '{"text": ${jsonEncode(text)}, "offsets": {"from": $from, "to": $to}, "p": $p}';

List<TimedWord> words(String text, {double start = 0, double step = 0.4, double confidence = 0.9}) => text
    .split(' ')
    .indexed
    .map((e) => TimedWord(e.$2, start + e.$1 * step, start + e.$1 * step + 0.3, confidence: confidence))
    .toList();

void main() {
  group('whisper', () {
    test('merges sub-word tokens into sentences and skips special tokens', () {
      final tokens = [
        token('[_BEG_]', 0, 0), token(' I', 0, 200), token(' can', 200, 400), token("'t", 400, 450),
        token(' go', 500, 700), token('.', 700, 750, 0.1), token(' See', 2500, 2700), token(' you', 2700, 2900), token('!', 2900, 3000),
      ].join(',');
      final transcript = parseWhisperJson(utf8.encode('{"transcription": [{"tokens": [$tokens]}]}'));
      expect(transcript.lines.map((l) => l.text), ['I can\'t go.', 'See you!']);
      expect(transcript.lines[0].words[1].start, 0.2);
      expect(transcript.lines[0].words[1].end, 0.45);
      expect(transcript.lines[0].words[2].confidence, 0.9, reason: 'punctuation does not lower confidence');
    });

    test('tolerates invalid UTF-8', () {
      final bytes = [...utf8.encode('{"transcription": [{"tokens": [{"text": " hi'), 0xE2, ...utf8.encode('", "offsets": {"from": 0, "to": 100}}]}]}')];
      expect(parseWhisperJson(bytes).lines.first.words.first.text, 'hi');
    });
  });

  group('transcript', () {
    final transcript = Transcript([
      TranscriptLine(0, 1, 3, [TimedWord('Good', 1, 1.5), TimedWord('morning.', 1.6, 3)]),
      TranscriptLine(1, 10, 12, [TimedWord('Morning,', 10, 11), TimedWord('friend', 11, 12)]),
    ]);
    test('finds the active line and word', () {
      expect(transcript.lineIndexAt(0.5), isNull);
      expect(transcript.lineIndexAt(1.7), 0);
      expect(transcript.lines[0].wordIndexAt(1.7), 1);
      expect(transcript.lineIndexAt(4), 0);
      expect(transcript.lineIndexAt(7), isNull);
      expect(transcript.lineIndexAt(11), 1);
    });
    test('nearest line for jumps into silence', () {
      expect(transcript.nearestLineIndex(7), 0);
      expect(transcript.nearestLineIndex(0), 0);
      expect(transcript.nearestLineIndex(50), 1);
    });
    test('lines containing a word', () {
      expect(transcript.linesContaining('MORNING!', limit: 3).map((l) => l.id), [0, 1]);
      expect(transcript.linesContaining('morning', limit: 1).map((l) => l.id), [0]);
    });
  });

  group('srt', () {
    test('parses blocks, removes tags and sound descriptions', () {
      const srt = '1\r\n00:00:01,000 --> 00:00:03,000\r\n<i>Hello there</i>\r\n\r\n'
          '2\r\n00:00:04,000 --> 00:00:05,000\r\n[THUNDER RUMBLES]\r\n\r\n'
          '3\r\n00:01:00,500 --> 00:01:02,000\r\nHow are\r\nyou?\r\n';
      final transcript = parseSrt(srt);
      expect(transcript.lines.map((l) => l.text), ['Hello there', 'How are you?']);
      expect(transcript.lines[1].start, 60.5);
      expect(transcript.lines[0].words.last.end, closeTo(3, 0.001));
    });
  });

  group('sound annotations', () {
    List<String> clean(String text) => cleanSoundAnnotations(words(text)).map((e) => e.$2.text).toList();
    test('removes descriptions, tags and music symbols', () {
      expect(clean('(background music playing) Hello there.'), ['Hello', 'there.']);
      expect(clean('[Music]. I can\'t [BLANK_AUDIO] go *sighs* now'), ['I', 'can\'t', 'go', 'now']);
      expect(clean('♪ We sing along ♪'), ['We', 'sing', 'along']);
      expect(clean('We\'re out.[MUSIC PLAYING][MUSIC PLAYING] No.(dramatic music) Go'), ['We\'re', 'out.', 'No.', 'Go']);
    });
    test('keeps real speech', () {
      expect(clean('(well I think we should leave now before the storm hits the harbor and the boats sink').length, 17);
      expect(clean('What the f*ck is that').length, 5);
    });
  });

  group('dictionary', () {
    test('normalizes words and suggests base forms', () {
      expect(lookupKey('“Don’t!”'), 'don\'t');
      expect(lookupKey('...'), '');
      expect(lookupCandidates("Let's"), contains('let'));
      expect(lookupCandidates('running'), contains('run'));
      expect(lookupCandidates('making'), contains('make'));
      expect(lookupCandidates('studied'), contains('study'));
      expect(lookupCandidates('movies'), contains('movie'));
    });
    test('parses Wiktionary with HTML and limits examples', () {
      final json = {
        'en': [
          {
            'partOfSpeech': 'Noun',
            'definitions': [
              {'definition': 'A <a href="x">sheltered</a> place for ships.', 'examples': ['The <b>harbor</b> was calm.', 'One', 'Two', 'Three']},
              {'definition': ''},
            ],
          },
        ],
      };
      final entry = parseWiktionary('harbor', json)!;
      expect(entry.senses.single.definition, 'A sheltered place for ships.');
      expect(entry.senses.single.partOfSpeech, 'noun');
      expect(entry.examples, ['The harbor was calm.', 'One', 'Two']);
    });
  });

  group('saved words and review', () {
    test('saved word list and CSV', () {
      final list = WordList()
        ..add(SavedWord(word: 'Harbor', definition: 'a place for ships'))
        ..add(SavedWord(word: 'storm', definition: 'wind, "rain"', translation: 'tempestade'))
        ..add(SavedWord(word: 'harbor!', definition: 'updated'));
      expect(list.words.map((w) => w.key), ['harbor', 'storm']);
      expect(list.words.first.definition, 'updated');
      expect(list.contains('STORM.'), isTrue);
      expect(list.filtered('tempest').single.key, 'storm');
      expect(WordList([SavedWord(word: 'storm', definition: 'wind, "rain"', translation: 'tempestade')]).csv(),
          'word,portuguese,phonetic,part of speech,definition,sentence,source\nstorm,tempestade,,,"wind, ""rain""",,\n');
      expect(SavedWord(word: 'x', sourcePath: r'C:\Videos\Tears of Steel [R6MlUcmOul8].mp4').sourceName, 'Tears of Steel');
    });

    test('spaced repetition schedule', () {
      final start = DateTime(2026, 1, 1);
      var state = nextReview(null, ReviewGrade.good, start);
      expect(state.interval, 1);
      state = nextReview(state, ReviewGrade.good, state.due);
      expect(state.interval, 3);
      state = nextReview(state, ReviewGrade.good, state.due);
      expect(state.interval, 8);
      final forgotten = nextReview(state, ReviewGrade.again, state.due);
      expect(forgotten.lapses, 1);
      expect(forgotten.due.difference(state.due), relearnDelay);
      expect(describeNextReview(null, ReviewGrade.again, start), '10 min');
      expect(describeNextReview(null, ReviewGrade.easy, start), '4 dias');

      final deck = WordList()..add(SavedWord(word: 'harbor'))..add(SavedWord(word: 'storm'));
      expect(deck.due(start).length, 2);
      deck.grade('storm', ReviewGrade.good, start);
      expect(deck.due(start).map((w) => w.key), ['harbor']);
      expect(deck.nextDueDate(start), start.add(const Duration(days: 1)));
      deck.add(SavedWord(word: 'storm', definition: 'again'));
      expect(deck.words.first.review?.interval, 1, reason: 'saving again keeps progress');

      final restored = WordList.fromJson(jsonDecode(jsonEncode(deck.toJson())) as Map<String, dynamic>);
      expect(restored.words.first.review?.interval, 1);
    });
  });

  group('pronunciation', () {
    final line = TranscriptLine(0, 10, 12.8, words('We need to leave the harbor before sunset.', start: 10, step: 0.35));
    test('scores attempts', () {
      final perfect = scorePronunciation(line, words('We need to leave the harbor before sunset.'));
      expect(perfect.score, greaterThanOrEqualTo(95));
      final oneWrong = scorePronunciation(line, words('We need to leave the harvard before sunset'));
      expect(oneWrong.words[5].status, WordStatus.wrong);
      expect(oneWrong.words[5].heard, 'harvard');
      expect(oneWrong.score, lessThan(90));
      final half = scorePronunciation(line, words('We need to leave'));
      expect(half.completeness, 0.5);
      expect(half.score, lessThan(60));
      expect(half.tips.any((t) => t.contains('rápido')), isFalse);
      final mumbled = scorePronunciation(line, words('We need to leave the harbor before sunset.', confidence: 0.2));
      expect(mumbled.words.every((w) => w.status == WordStatus.unsure), isTrue);
      expect(scorePronunciation(line, []).score, 0);
      final numbers = TranscriptLine(1, 0, 2, words('four three two one'));
      expect(scorePronunciation(numbers, words('4 3 2 1')).score, greaterThanOrEqualTo(95));
    });

    test('history', () {
      final history = PracticeHistory()
        ..add(PracticeAttempt(date: DateTime(2026), score: 60, recognizedText: ''), sentence: 'A', source: 'Film', lineStart: 1)
        ..add(PracticeAttempt(date: DateTime(2026, 2), score: 90, recognizedText: ''), sentence: 'A', source: 'Film', lineStart: 1)
        ..add(PracticeAttempt(date: DateTime(2026, 3), score: 40, recognizedText: ''), sentence: 'B', source: 'Film', lineStart: 5);
      expect(history.record('A', 'Film')?.best, 90);
      expect(history.attemptCount, 3);
      expect(history.recent.first.sentence, 'B');
      expect(history.averageScore, 65);
      final restored = PracticeHistory.fromJson(jsonDecode(jsonEncode(history.toJson())) as Map<String, dynamic>);
      expect(restored.record('A', 'Film')?.attempts.length, 2);
    });
  });
}
