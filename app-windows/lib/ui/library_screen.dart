import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_controller.dart';
import '../services/paths.dart';
import '../services/stores.dart';
import 'common.dart';
import 'home.dart';
import 'review_screen.dart';

/// Home screen: featured item and rows of covers, Netflix style.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = app.library;
    final featured = library.featured;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (featured != null) _Hero(item: featured),
        _Row('Continuar assistindo', library.continueWatching),
        _Row('Baixados do YouTube', library.downloads),
        _Row('Filmes e vídeos', library.videos),
        _Row('Músicas', library.music),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: openMediaFile, icon: const Icon(Icons.folder_open), label: const Text('Abrir arquivo…')),
            OutlinedButton.icon(onPressed: () => showLinkDialog(context), icon: const Icon(Icons.link), label: const Text('Baixar do YouTube…')),
            if (app.savedWords.list.due().isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: accentOrange),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewScreen())),
                icon: const Icon(Icons.style),
                label: Text('Revisar palavras (${app.savedWords.list.due().length})'),
              ),
            if (library.downloadsSize > 0) ...[
              Text('Downloads: ${formatBytes(library.downloadsSize)}', style: const TextStyle(color: Colors.white54)),
              TextButton(onPressed: () => launchUrl(Uri.directory(AppPaths.downloads.path)), child: const Text('Mostrar pasta')),
            ],
          ]),
        ),
      ],
    );
  }
}

void _play(LibraryItem item, {bool fromStart = false}) =>
    app.open(item.path, at: !fromStart && item.isInProgress ? item.position : null);

Future<void> _remove(BuildContext context, LibraryItem item) async {
  if (!item.isDownload) return app.library.forget(item);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Apagar “${item.title}”?'),
      content: Text('O vídeo (${formatBytes(item.size)}) e a transcrição serão apagados. '
          'As palavras salvas e o histórico de pronúncia continuam.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );
  if (confirmed == true) app.library.delete(item);
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Stack(fit: StackFit.expand, children: [
        _Cover(item: item, showTitle: false),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF141419)]),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.center, colors: [Color(0xC0000000), Colors.transparent]),
          ),
        ),
        Positioned(
          left: 32,
          bottom: 28,
          right: 32,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.lastOpened == null ? 'NOVO NA BIBLIOTECA' : 'ASSISTIDO RECENTEMENTE',
                style: const TextStyle(color: accentOrange, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Text(item.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            _Details(item: item),
            if (item.isInProgress) ...[
              const SizedBox(height: 10),
              SizedBox(width: 260, child: LinearProgressIndicator(value: item.progress, color: accentOrange)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                onPressed: () => _play(item),
                icon: const Icon(Icons.play_arrow),
                label: Text(item.isInProgress ? 'Continuar' : 'Assistir'),
              ),
              if (item.isInProgress) ...[
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: () => _play(item, fromStart: true),
                  icon: const Icon(Icons.replay),
                  label: const Text('Do início'),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.items);
  final String title;
  final List<LibraryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) => _Card(item: items[index]),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({required this.item});
  final LibraryItem item;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _play(item),
        onSecondaryTapDown: (details) => _menu(context, details.globalPosition),
        child: SizedBox(
          width: 256,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedScale(
              scale: _hovered ? 1.06 : 1,
              duration: const Duration(milliseconds: 150),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 256,
                  height: 144,
                  child: Stack(fit: StackFit.expand, children: [
                    _Cover(item: item, showTitle: true),
                    if (item.isInProgress)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: LinearProgressIndicator(value: item.progress, color: accentOrange, backgroundColor: Colors.white30),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(children: [
                        if (item.hasTranscript) const _Badge('CC', 'Legendas prontas'),
                        if (item.isAudio) const _Badge('♪', 'Música'),
                      ]),
                    ),
                    if (_hovered) ...[
                      const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white)),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          icon: Icon(item.isDownload ? Icons.delete_outline : Icons.close, size: 18),
                          tooltip: item.isDownload ? 'Apagar o vídeo baixado' : 'Remover da biblioteca (o arquivo continua no computador)',
                          onPressed: () => _remove(context, item),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            _Details(item: item, small: true),
          ]),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Offset position) async {
    final item = widget.item;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: 'play', child: Text(item.isInProgress ? 'Continuar' : 'Assistir')),
        if (item.isInProgress) const PopupMenuItem(value: 'start', child: Text('Assistir do início')),
        const PopupMenuItem(value: 'folder', child: Text('Mostrar na pasta')),
        PopupMenuItem(value: 'remove', child: Text(item.isDownload ? 'Apagar vídeo…' : 'Remover da biblioteca')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'play':
        _play(item);
      case 'start':
        _play(item, fromStart: true);
      case 'folder':
        launchUrl(Uri.directory(File(item.path).parent.path));
      case 'remove':
        _remove(context, item);
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.tooltip);
  final String text, tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(3)),
          child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
}

class _Details extends StatelessWidget {
  const _Details({required this.item, this.small = false});
  final LibraryItem item;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (item.duration != null) formatDuration(item.duration!),
      if (item.isInProgress) 'faltam ${formatDuration(item.duration! - item.position!)}',
      formatBytes(item.size),
    ];
    return Text(parts.join(' · '), style: TextStyle(color: Colors.white60, fontSize: small ? 12 : 14));
  }
}

/// The cover image, or a colored placeholder with the title.
class _Cover extends StatelessWidget {
  const _Cover({required this.item, required this.showTitle});
  final LibraryItem item;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final file = app.library.thumbnails[item.path];
    if (file != null) return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
    // A fixed hue per title, so each placeholder looks different.
    final hue = item.title.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) % 360).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          HSVColor.fromAHSV(1, hue, 0.6, 0.55).toColor(),
          HSVColor.fromAHSV(1, (hue + 40) % 360, 0.7, 0.3).toColor(),
        ]),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(item.isAudio ? Icons.music_note : Icons.movie, size: 32, color: Colors.white70),
          if (showTitle)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(item.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
  }
}
