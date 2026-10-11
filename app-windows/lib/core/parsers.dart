import 'dart:convert';

import 'sound_annotations.dart';
import 'transcript.dart';

final _punctuationOnly = RegExp(r'^[\p{P}]+$', unicode: true);

/// Parses the "full JSON" output of whisper.cpp (`whisper-cli -ojf`).
Transcript parseWhisperJson(List<int> bytes) {
  // Tokens can split multi-byte characters (e.g. "♪"); decode leniently.
  final root = jsonDecode(utf8.decode(bytes, allowMalformed: true)) as Map<String, dynamic>;
  final words = <TimedWord>[];
  final segmentBreaks = <int>{};

  for (final segment in (root['transcription'] as List? ?? [])) {
    for (final token in ((segment as Map)['tokens'] as List? ?? [])) {
      final raw = (token as Map)['text'] as String;
      if (raw.startsWith('[_')) continue; // special tokens like [_BEG_]
      final text = raw.replaceAll('�', '');
      final trimmed = text.trim();
      if (trimmed.isEmpty) continue;

      final offsets = token['offsets'] as Map;
      final start = (offsets['from'] as num) / 1000;
      final end = (offsets['to'] as num) / 1000;
      final punctuation = _punctuationOnly.hasMatch(trimmed);
      // Punctuation probabilities say nothing about how a word was pronounced.
      final confidence = punctuation ? null : (token['p'] as num?)?.toDouble();

      if ((text.startsWith(' ') && !punctuation) || words.isEmpty) {
        words.add(TimedWord(trimmed, start, end, confidence: confidence));
      } else {
        // Sub-word piece or punctuation: glue to the previous word.
        final last = words.last;
        last.text += trimmed;
        if (end > last.end) last.end = end;
        if (confidence != null) {
          last.confidence = last.confidence == null ? confidence : (confidence < last.confidence! ? confidence : last.confidence);
        }
      }
    }
    if (words.isNotEmpty) segmentBreaks.add(words.length - 1);
  }
  return removeSoundAnnotations(Transcript(buildLines(words, segmentBreaks: segmentBreaks)));
}

/// Parses .srt subtitles. Word timings are estimated by spreading each line's duration.
Transcript parseSrt(String contents) {
  final normalized = contents.replaceAll('\r\n', '\n').replaceAll('﻿', '');
  final lines = <TranscriptLine>[];
  for (final block in normalized.split('\n\n')) {
    final rows = block.split('\n').where((r) => r.trim().isNotEmpty).toList();
    final timeRow = rows.indexWhere((r) => r.contains('-->'));
    if (timeRow < 0) continue;
    final times = rows[timeRow].split('-->');
    final start = parseSrtTime(times[0]);
    final end = times.length > 1 ? parseSrtTime(times[1]) : null;
    if (start == null || end == null) continue;
    final text = rows.sublist(timeRow + 1).join(' ').replaceAll(RegExp(r'<[^>]+>'), '');
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) continue;

    final total = tokens.fold<int>(0, (sum, t) => sum + t.length + 1);
    final duration = end - start > 0.1 ? end - start : 0.1;
    var cursor = start;
    final words = tokens.map((t) {
      final length = duration * (t.length + 1) / total;
      final word = TimedWord(t, cursor, cursor + length);
      cursor += length;
      return word;
    }).toList();
    lines.add(TranscriptLine(lines.length, start, end, words));
  }
  return removeSoundAnnotations(Transcript(lines));
}

/// "00:01:02,500" -> 62.5
double? parseSrtTime(String raw) {
  final parts = raw.trim().split(' ').first.replaceAll(',', '.').split(':');
  if (parts.length != 3) return null;
  final h = double.tryParse(parts[0]), m = double.tryParse(parts[1]), s = double.tryParse(parts[2]);
  if (h == null || m == null || s == null) return null;
  return h * 3600 + m * 60 + s;
}
