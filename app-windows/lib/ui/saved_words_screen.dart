import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/saved_words.dart';
import '../services/app_controller.dart';
import 'common.dart';
import 'review_screen.dart';

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
        return Scaffold(
          appBar: AppBar(
            title: Text('Palavras salvas (${list.words.length})'),
            actions: [
              TextButton.icon(
                onPressed: list.words.isEmpty
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewScreen())),
                icon: const Icon(Icons.style),
                label: Text('Revisar (${list.due().length})'),
              ),
              TextButton.icon(
                onPressed: list.words.isEmpty ? null : _export,
                icon: const Icon(Icons.file_download),
                label: const Text('Exportar CSV'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: list.words.isEmpty
              ? const Center(
                  child: Text('Nenhuma palavra salva ainda.\nClique numa palavra da legenda e toque em 🔖 para guardá-la aqui.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search), hintText: 'Buscar palavra, tradução, significado ou frase', border: OutlineInputBorder()),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: words.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _WordRow(word: words[index]),
                    ),
                  ),
                ]),
        );
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

class _WordRow extends StatelessWidget {
  const _WordRow({required this.word});
  final SavedWord word;

  @override
  Widget build(BuildContext context) {
    final review = word.review;
    final status = review?.isMastered == true
        ? const Text('Dominada ✓', style: TextStyle(color: Colors.green, fontSize: 12))
        : review != null && review.due.isAfter(DateTime.now())
            ? Text('Revisão ${relativeTime(review.due)}', style: const TextStyle(color: Colors.white54, fontSize: 12))
            : const Text('Revisar agora', style: TextStyle(color: accentOrange, fontSize: 12));
    final source = word.sourcePath;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(word.word, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (word.translation != null) Text('  ·  ${word.translation}', style: const TextStyle(fontSize: 18)),
          if (word.phonetic != null) Text('  ${word.phonetic}', style: const TextStyle(color: Colors.white54)),
          const Spacer(),
          status,
          IconButton(icon: const Icon(Icons.volume_up, size: 20), tooltip: 'Ouvir', onPressed: () => app.speaker.say(word.word)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Remover da lista',
            onPressed: () => app.savedWords.remove(word.key),
          ),
        ]),
        if (word.definition != null) SelectableText(word.definition!),
        if (word.context != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(
                child: Text('“${word.context}”${word.sourceName != null ? '  —  ${word.sourceName}' : ''}',
                    style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
              ),
              if (source != null && File(source).existsSync())
                TextButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    app.open(source, at: word.sourceTime ?? 0);
                  },
                  child: const Text('Ir para o trecho'),
                ),
            ]),
          ),
      ]),
    );
  }
}
