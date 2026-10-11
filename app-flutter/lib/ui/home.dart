import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import '../services/media_tools.dart';
import '../services/stores.dart';
import 'common.dart';
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
      builder: (context, _) => PopScope(
        // Android back button: from the player back to the library.
        canPop: app.mediaPath == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) app.closeMedia();
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1C1C24),
            leading: app.mediaPath == null
                ? null
                : IconButton(icon: const Icon(Icons.grid_view_rounded), tooltip: 'Voltar para a biblioteca', onPressed: app.closeMedia),
            title: Text(app.sourceName ?? (isCompact(context) ? 'English with Movies' : 'English with Movies & Music'),
                overflow: TextOverflow.ellipsis),
            actions: isCompact(context) ? _compactActions(context) : _actions(context),
          ),
          body: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    final content = Column(
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
    );
    if (isMobile) return content;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) unawaited(app.open(details.files.first.path));
      },
      child: content,
    );
  }

  Widget _savedWordsIcon() => Badge(
        isLabelVisible: app.savedWords.list.due().isNotEmpty,
        label: Text('${app.savedWords.list.due().length}'),
        child: const Icon(Icons.bookmark_outline),
      );

  Widget _translationButton(BuildContext context) => IconButton(
        icon: Icon(Icons.translate, color: app.showTranslation ? Theme.of(context).colorScheme.primary : null),
        tooltip: 'Mostrar a tradução da fala atual',
        onPressed: () => app.setShowTranslation(!app.showTranslation),
      );

  List<Widget> _actions(BuildContext context) => [
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
        _translationButton(context),
        if (!isMobile) IconButton(icon: const Icon(Icons.link), tooltip: 'Baixar do YouTube', onPressed: () => showLinkDialog(context)),
        IconButton(icon: const Icon(Icons.closed_caption_outlined), tooltip: 'Importar legenda (.srt)', onPressed: _importSrt),
        IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Abrir arquivo', onPressed: openMediaFile),
        IconButton(icon: _savedWordsIcon(), tooltip: 'Palavras salvas', onPressed: () => _push(const SavedWordsScreen())),
        IconButton(icon: const Icon(Icons.style_outlined), tooltip: 'Revisar palavras', onPressed: () => _push(const ReviewScreen())),
        IconButton(
          icon: const Icon(Icons.bar_chart),
          tooltip: 'Histórico de pronúncia',
          onPressed: () => _push(const PracticeHistoryScreen()),
        ),
        const SizedBox(width: 8),
      ];

  /// Phone: the most used buttons, the rest in a menu.
  List<Widget> _compactActions(BuildContext context) => [
        _translationButton(context),
        IconButton(icon: _savedWordsIcon(), tooltip: 'Palavras salvas', onPressed: () => _push(const SavedWordsScreen())),
        PopupMenuButton<VoidCallback>(
          onSelected: (action) => action(),
          itemBuilder: (context) {
            PopupMenuItem<VoidCallback> item(IconData icon, String title, VoidCallback action, {bool enabled = true}) =>
                PopupMenuItem(value: action, enabled: enabled, child: ListTile(leading: Icon(icon), title: Text(title)));
            return [
              item(Icons.folder_open, 'Abrir arquivo', openMediaFile),
              if (!isMobile) item(Icons.link, 'Baixar do YouTube', () => showLinkDialog(context)),
              item(Icons.closed_caption_outlined, 'Importar legenda (.srt)', _importSrt),
              item(Icons.style_outlined, 'Revisar palavras', () => _push(const ReviewScreen())),
              item(Icons.bar_chart, 'Histórico de pronúncia', () => _push(const PracticeHistoryScreen())),
              item(Icons.refresh, 'Transcrever de novo', app.retranscribe, enabled: app.mediaPath != null),
              item(Icons.tune, 'Qualidade da transcrição', () => _chooseModel(context)),
            ];
          },
        ),
      ];

  Future<void> _chooseModel(BuildContext context) async {
    final chosen = await showDialog<WhisperModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Qualidade da transcrição'),
        children: [
          for (final m in WhisperModel.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Row(children: [
                Icon(m == app.model ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(m.title)),
              ]),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text('No celular, os modelos maiores são bem mais lentos.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        ],
      ),
    );
    if (chosen != null) app.setModel(chosen);
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _importSrt() async {
    // Phones do not know a MIME type for .srt, so any file can be chosen there.
    final path = (await FilePicker.pickFile(
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : ['srt'],
    ))
        ?.path;
    if (path != null) app.importSubtitles(path);
  }
}

Future<void> openMediaFile() async {
  final file = await FilePicker.pickFile(
    type: isMobile ? FileType.media : FileType.custom,
    allowedExtensions: isMobile ? null : [...LibraryStore.videoExtensions, ...LibraryStore.audioExtensions],
    // On a phone the file is copied before the picker returns; a film takes a while.
    onFileLoading: (status) => app.showImporting(status == FilePickerStatus.picking),
  );
  app.showImporting(false);
  final path = file?.path;
  if (path == null) return;
  app.open(isMobile ? await app.importIntoLibrary(path) : path);
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
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_filter_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          Text(isMobile ? 'Escolha um filme ou uma música' : 'Arraste um filme ou uma música aqui',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            isMobile
                ? 'O app transcreve as falas, mostra a legenda em tempo real e explica qualquer palavra em que você tocar.'
                : 'O app transcreve as falas, mostra a legenda em tempo real\ne explica qualquer palavra em que você clicar.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(onPressed: openMediaFile, icon: const Icon(Icons.folder_open), label: const Text('Escolher arquivo…')),
            if (!isMobile)
              OutlinedButton.icon(onPressed: () => showLinkDialog(context), icon: const Icon(Icons.link), label: const Text('Baixar do YouTube…')),
          ]),
        ]),
      ),
    );
  }
}
