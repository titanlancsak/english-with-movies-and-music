import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import '../services/media_tools.dart';
import '../services/stores.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'practice_history_screen.dart';
import 'review_screen.dart';
import 'saved_words_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;
  final _missingTools = MediaTools.missingTools();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.library, app.savedWords]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF1C1C24),
          leading: app.mediaPath == null
              ? null
              : IconButton(icon: const Icon(Icons.grid_view_rounded), tooltip: 'Voltar para a biblioteca', onPressed: app.closeMedia),
          title: Text(app.sourceName ?? 'English with Movies & Music', overflow: TextOverflow.ellipsis),
          actions: [
            DropdownButtonHideUnderline(
              child: DropdownButton<WhisperModel>(
                value: app.model,
                items: [for (final m in WhisperModel.values) DropdownMenuItem(value: m, child: Text(m.title))],
                onChanged: (m) => app.setModel(m!),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Transcrever de novo',
              onPressed: app.mediaPath == null ? null : app.retranscribe,
            ),
            IconButton(
              icon: Icon(Icons.translate, color: app.showTranslation ? Theme.of(context).colorScheme.primary : null),
              tooltip: 'Mostrar a tradução da fala atual',
              onPressed: () => app.setShowTranslation(!app.showTranslation),
            ),
            IconButton(icon: const Icon(Icons.link), tooltip: 'Baixar do YouTube', onPressed: () => showLinkDialog(context)),
            IconButton(icon: const Icon(Icons.closed_caption_outlined), tooltip: 'Importar legenda (.srt)', onPressed: _importSrt),
            IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Abrir arquivo', onPressed: openMediaFile),
            IconButton(
              icon: Badge(
                isLabelVisible: app.savedWords.list.due().isNotEmpty,
                label: Text('${app.savedWords.list.due().length}'),
                child: const Icon(Icons.bookmark_outline),
              ),
              tooltip: 'Palavras salvas',
              onPressed: () => _push(const SavedWordsScreen()),
            ),
            IconButton(icon: const Icon(Icons.style_outlined), tooltip: 'Revisar palavras', onPressed: () => _push(const ReviewScreen())),
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: 'Histórico de pronúncia',
              onPressed: () => _push(const PracticeHistoryScreen()),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            if (details.files.isNotEmpty) unawaited(app.open(details.files.first.path));
          },
          child: Column(
            children: [
              if (_missingTools.isNotEmpty)
                MaterialBanner(
                  content: Text('Faltam programas: ${_missingTools.join(', ')}. Baixe o app completo na página de Releases do GitHub.'),
                  actions: const [SizedBox.shrink()],
                ),
              const StatusBar(),
              Expanded(
                child: app.mediaPath != null
                    ? const PlayerScreen()
                    : app.library.items.isEmpty
                        ? DropZone(dragging: _dragging)
                        : const LibraryScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _importSrt() async {
    final path = (await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['srt']))?.path;
    if (path != null) app.importSubtitles(path);
  }
}

Future<void> openMediaFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: [...LibraryStore.videoExtensions, ...LibraryStore.audioExtensions],
  );
  final path = file?.path;
  if (path != null) app.open(path);
}

Future<void> showLinkDialog(BuildContext context) async {
  final controller = TextEditingController();
  final link = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Baixar do YouTube'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cole o link do vídeo. Ele é baixado, transcrito e fica salvo na sua biblioteca (Vídeos › English with Movies).'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'https://www.youtube.com/watch?v=…', border: OutlineInputBorder()),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Baixar')),
      ],
    ),
  );
  if (link != null && Uri.tryParse(link.trim())?.hasAuthority == true) app.download(link);
}

/// Progress or error of the current task. Listens to the app itself: as a const
/// widget it would not be rebuilt when its parent rebuilds.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    switch (app.status) {
      case Status.working:
        return Container(
          color: const Color(0xFF1C1C24),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.message),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: app.progress),
              ]),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: app.cancel, child: const Text('Cancelar')),
          ]),
        );
      case Status.failed:
        return Container(
          color: const Color(0xFF2A1F1A),
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(app.message)),
            if (app.mediaPath != null) TextButton(onPressed: app.retranscribe, child: const Text('Tentar de novo')),
          ]),
        );
      case Status.idle:
      case Status.ready:
        return const SizedBox.shrink();
    }
  }
}

class DropZone extends StatelessWidget {
  const DropZone({super.key, required this.dragging});
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: dragging ? Theme.of(context).colorScheme.primary : Colors.white24, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_filter_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          Text('Arraste um filme ou uma música aqui', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'O app transcreve as falas, mostra a legenda em tempo real\ne explica qualquer palavra em que você clicar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(onPressed: openMediaFile, icon: const Icon(Icons.folder_open), label: const Text('Escolher arquivo…')),
            const SizedBox(width: 12),
            OutlinedButton.icon(onPressed: () => showLinkDialog(context), icon: const Icon(Icons.link), label: const Text('Baixar do YouTube…')),
          ]),
        ]),
      ),
    );
  }
}
