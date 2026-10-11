import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/saved_words.dart';
import '../services/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// The saved words, as cards with search, review and export.
class SavedWordsScreen extends StatefulWidget {
  const SavedWordsScreen({super.key});

  @override
  State<SavedWordsScreen> createState() => _SavedWordsScreenState();
}

class _SavedWordsScreenState extends State<SavedWordsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.savedWords,
      builder: (context, _) {
        final list = app.savedWords.list;
        final words = list.filtered(_query);
        final compact = isCompact(context);
        final margin = compact ? 16.0 : 28.0;
        final mastered = list.masteredCount();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(margin, 12, margin, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ScreenTitle('Palavras salvas',
                    subtitle: '${list.words.length} palavra${list.words.length == 1 ? '' : 's'} · $mastered dominada${mastered == 1 ? '' : 's'}'),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  GlassButton(label: 'Exportar CSV', icon: Icons.ios_share_rounded, onPressed: list.words.isEmpty ? null : _export),
                  const SizedBox(width: 10),
                  PrimaryButton(
                    label: 'Revisar (${list.due().length})',
                    icon: Icons.style_rounded,
                    onPressed: list.words.isEmpty ? null : () => app.showSection(AppSection.review),
                  ),
                ]),
              ],
            ),
          ),
          if (list.words.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(margin, 16, margin, 4),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: AppColors.textDim),
                  hintText: 'Buscar palavra, tradução, significado ou frase',
                  hintStyle: const TextStyle(color: AppColors.textDim),
                  filled: true,
                  fillColor: AppColors.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.stroke)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.violet)),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          Expanded(
            child: list.words.isEmpty
                ? const EmptyState(
                    icon: Icons.bookmark_rounded,
                    title: 'Nenhuma palavra salva ainda',
                    text: 'Toque numa palavra da legenda e depois em 🔖 para guardá-la aqui.')
                : words.isEmpty
                    ? EmptyState(icon: Icons.search, title: 'Nada encontrado', text: 'Nenhuma palavra combina com “$_query”.')
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(margin, 12, margin, 24),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisExtent: compact ? 230 : 220,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: words.length,
                        itemBuilder: (context, index) => _WordCard(word: words[index]),
                      ),
          ),
        ]);
      },
    );
  }

  Future<void> _export() async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Exportar palavras',
      fileName: 'palavras-salvas.csv',
      bytes: Uint8List.fromList(utf8.encode(app.savedWords.list.csv())),
      mimeType: 'text/csv',
    );
    if (saved == null) return;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Palavras exportadas.')));
  }
}

class _WordCard extends StatefulWidget {
  const _WordCard({required this.word});
  final SavedWord word;

  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final review = word.review;
    final status = review?.isMastered == true
        ? const TagChip('Dominada', icon: Icons.verified_rounded, color: AppColors.green)
        : review != null && review.due.isAfter(DateTime.now())
            ? TagChip('Revisão ${relativeTime(review.due)}', icon: Icons.schedule, color: AppColors.textDim)
            : const TagChip('Revisar agora', icon: Icons.bolt_rounded, color: AppColors.orange);
    final source = word.sourcePath;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GlassCard(
        highlighted: _hovered,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
                  Text(word.word, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  if (word.phonetic != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(word.phonetic!, style: const TextStyle(color: AppColors.textDim)),
                    ),
                ]),
                if (word.translation != null)
                  Text(word.translation!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.orange)),
              ]),
            ),
            status,
          ]),
          const SizedBox(height: 8),
          if (word.definition != null)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (word.partOfSpeech != null) ...[TagChip(word.partOfSpeech!, color: AppColors.violet), const SizedBox(width: 6)],
              Expanded(child: Text(word.definition!, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          if (word.context != null) ...[
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3, decoration: BoxDecoration(gradient: AppColors.brand, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(word.context!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
                    if (word.sourceName != null)
                      Text(word.sourceName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                  ]),
                ),
              ]),
            ),
          ],
          const Spacer(),
          Row(children: [
            GlassIconButton(icon: Icons.volume_up_rounded, tooltip: 'Ouvir a pronúncia', size: 30, onPressed: () => app.speaker.say(word.word)),
            const SizedBox(width: 8),
            if (source != null && File(source).existsSync())
              GlassButton(label: 'Ir para o trecho', icon: Icons.play_arrow_rounded, onPressed: () => app.open(source, at: word.sourceTime ?? 0)),
            const Spacer(),
            if (_hovered || isMobile)
              GlassIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Remover da lista',
                size: 30,
                color: AppColors.textDim,
                onPressed: () => app.savedWords.remove(word.key),
              ),
          ]),
        ]),
      ),
    );
  }
}
