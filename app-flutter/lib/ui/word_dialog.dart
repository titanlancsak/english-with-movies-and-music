import 'package:flutter/material.dart';

import '../core/dictionary.dart';
import '../core/saved_words.dart';
import '../core/transcript.dart';
import '../core/word_normalizer.dart';
import '../services/app_controller.dart';
import 'common.dart';

Future<void> showWordDialog(BuildContext context, String word, TranscriptLine line) =>
    showDialog(context: context, builder: (_) => WordDialog(word: word, line: line));

/// Definition, pronunciation, translation and up to 3 examples of a clicked word.
class WordDialog extends StatefulWidget {
  const WordDialog({super.key, required this.word, required this.line});
  final String word;
  final TranscriptLine line;

  @override
  State<WordDialog> createState() => _WordDialogState();
}

class _WordDialogState extends State<WordDialog> {
  late final Future<DictionaryEntry?> _entry = app.dictionary.lookup(widget.word);
  late final Future<String?> _translation = app.translator.translate(lookupKey(widget.word));
  late final Future<String?> _sentence = app.translator.translate(widget.line.text);

  @override
  Widget build(BuildContext context) {
    final key = lookupKey(widget.word);
    return Dialog(
      insetPadding: isCompact(context) ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: FutureBuilder<DictionaryEntry?>(
          future: _entry,
          builder: (context, snapshot) {
            final entry = snapshot.data;
            final loading = snapshot.connectionState != ConnectionState.done;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Text(entry?.word ?? key, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  if (entry?.phonetic != null) ...[
                    const SizedBox(width: 8),
                    Text(entry!.phonetic!, style: const TextStyle(color: Colors.white60)),
                  ],
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.volume_up), tooltip: 'Ouvir a pronúncia', onPressed: () => app.speaker.say(key)),
                  ListenableBuilder(
                    listenable: app.savedWords,
                    builder: (context, _) {
                      final saved = app.savedWords.contains(key);
                      return IconButton(
                        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline, color: saved ? accentOrange : null),
                        tooltip: saved ? 'Remover das palavras salvas' : 'Salvar palavra',
                        onPressed: loading ? null : () => _toggleSaved(entry, saved),
                      );
                    },
                  ),
                ]),
                const Divider(),
                if (loading)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (entry == null)
                  const Text('Não encontrei esta palavra no dicionário.', style: TextStyle(color: Colors.white60))
                else
                  for (final sense in entry.senses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(sense.partOfSpeech, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white54, fontSize: 12)),
                        SelectableText(sense.definition),
                      ]),
                    ),
                const SizedBox(height: 8),
                const Text('Em português', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                FutureBuilder<String?>(
                  future: _translation,
                  builder: (context, t) => Text('$key → ${t.data ?? (t.connectionState == ConnectionState.done ? app.translator.problem ?? '–' : 'traduzindo…')}'),
                ),
                const SizedBox(height: 4),
                FutureBuilder<String?>(
                  future: _sentence,
                  builder: (context, t) => Text(t.data ?? '', style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 12),
                ..._examples(entry),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Up to 3 examples: dictionary first, then lines from this movie or song (click to listen).
  List<Widget> _examples(DictionaryEntry? entry) {
    final fromDictionary = (entry?.examples ?? []).take(maxExamples).toList();
    final remaining = maxExamples - fromDictionary.length;
    final fromMedia = remaining > 0 ? app.transcript?.linesContaining(widget.word, limit: remaining) ?? [] : <TranscriptLine>[];
    if (fromDictionary.isEmpty && fromMedia.isEmpty) return [];
    return [
      const Text('Exemplos', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      for (final example in fromDictionary)
        ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.format_quote, size: 18), title: Text(example)),
      for (final line in fromMedia)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(app.isAudio ? Icons.music_note : Icons.movie, size: 18),
          title: Text(line.text),
          subtitle: const Text('Clique para ouvir este trecho'),
          onTap: () {
            Navigator.pop(context);
            app.playSegment(line);
          },
        ),
    ];
  }

  Future<void> _toggleSaved(DictionaryEntry? entry, bool saved) async {
    final key = lookupKey(widget.word);
    if (saved) return app.savedWords.remove(key);
    final sense = entry?.senses.firstOrNull;
    app.savedWords.add(SavedWord(
      word: entry?.word ?? key,
      phonetic: entry?.phonetic,
      partOfSpeech: sense?.partOfSpeech,
      definition: sense?.definition,
      translation: await _translation,
      context: widget.line.text,
      sourcePath: app.mediaPath,
      sourceTime: widget.line.start,
    ));
  }
}
