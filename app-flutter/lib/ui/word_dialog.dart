import 'package:flutter/material.dart';

import '../core/dictionary.dart';
import '../core/saved_words.dart';
import '../core/transcript.dart';
import '../core/word_normalizer.dart';
import '../services/app_controller.dart';
import 'common.dart';
import 'theme.dart';

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
      clipBehavior: Clip.antiAlias,
      insetPadding: isCompact(context) ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: FutureBuilder<DictionaryEntry?>(
          future: _entry,
          builder: (context, snapshot) {
            final entry = snapshot.data;
            final loading = snapshot.connectionState != ConnectionState.done;
            return Stack(children: [
              // A violet glow in the corner.
              Positioned(
                left: -80,
                top: -100,
                child: IgnorePointer(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [AppColors.violet.withValues(alpha: 0.35), AppColors.violet.withValues(alpha: 0)]),
                    ),
                  ),
                ),
              ),
              ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(22),
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        GradientText(entry?.word ?? key, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                        if (entry?.phonetic != null) Text(entry!.phonetic!, style: const TextStyle(color: AppColors.textDim)),
                      ]),
                    ),
                    GlassIconButton(icon: Icons.volume_up_rounded, tooltip: 'Ouvir a pronúncia', onPressed: () => app.speaker.say(key)),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                      listenable: app.savedWords,
                      builder: (context, _) {
                        final saved = app.savedWords.contains(key);
                        return GlassIconButton(
                          icon: saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                          color: saved ? AppColors.orange : Colors.white,
                          tooltip: saved ? 'Remover das palavras salvas' : 'Salvar palavra',
                          onPressed: loading ? null : () => _toggleSaved(entry, saved),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (loading)
                    const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.violet)))
                  else if (entry == null)
                    const Text('Não encontrei esta palavra no dicionário.', style: TextStyle(color: AppColors.textDim))
                  else
                    for (final sense in entry.senses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          TagChip(sense.partOfSpeech, color: AppColors.violet),
                          const SizedBox(height: 4),
                          SelectableText(sense.definition),
                        ]),
                      ),
                  const SizedBox(height: 8),
                  const SectionLabel('Em português'),
                  const SizedBox(height: 6),
                  FutureBuilder<String?>(
                    future: _translation,
                    builder: (context, t) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text(key, style: const TextStyle(color: AppColors.textDim)),
                      const Text('  →  ', style: TextStyle(color: AppColors.textDim)),
                      Flexible(
                        child: Text(t.data ?? (t.connectionState == ConnectionState.done ? app.translator.problem ?? '–' : 'traduzindo…'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.orange)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<String?>(
                    future: _sentence,
                    builder: (context, t) => Text(t.data ?? '', style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                  ),
                  const SizedBox(height: 16),
                  ..._examples(entry),
                ],
              ),
            ]);
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
      const SectionLabel('Exemplos'),
      const SizedBox(height: 8),
      for (final example in fromDictionary)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, decoration: BoxDecoration(gradient: AppColors.brand, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(child: Text(example)),
            ]),
          ),
        ),
      for (final line in fromMedia)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.pop(context);
            app.playSegment(line);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(app.isAudio ? Icons.music_note_rounded : Icons.play_circle_fill_rounded, size: 18, color: AppColors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(line.text),
                  Text(isMobile ? 'Toque para ouvir este trecho' : 'Clique para ouvir este trecho',
                      style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                ]),
              ),
            ]),
          ),
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
