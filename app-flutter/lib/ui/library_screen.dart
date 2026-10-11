import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_controller.dart';
import '../services/paths.dart';
import '../services/stores.dart';
import 'common.dart';
import 'theme.dart';

/// Home screen: a greeting with the study numbers, the featured item and rows of covers.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([app.library, app.savedWords, app.practice, app.study]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final library = app.library;
    final featured = library.featured;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        const _Header(),
        const SizedBox(height: 20),
        if (featured != null) _Hero(item: featured),
        _Row('Continuar assistindo', library.continueWatching),
        // On a phone every file is imported into the app, so there is no separate "downloads" row.
        if (isMobile)
          _Row('Filmes e vídeos', library.items.where((i) => !i.isAudio).toList())
        else ...[
          _Row('Baixados do YouTube', library.downloads),
          _Row('Filmes e vídeos', library.videos),
        ],
        _Row('Músicas', library.music),
        if (library.downloadsSize > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(_margin(context), 18, _margin(context), 0),
            child: Row(children: [
              Text('${isMobile ? 'Espaço usado' : 'Downloads'}: ${formatBytes(library.downloadsSize)}',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              if (!isMobile)
                TextButton(onPressed: () => launchUrl(Uri.directory(AppPaths.downloads.path)), child: const Text('Mostrar pasta')),
            ]),
          ),
      ],
    );
  }
}

/// "Boa noite!" and the study numbers; each card opens its screen.
class _Header extends StatelessWidget {
  const _Header();

  static String get _greeting {
    final hour = DateTime.now().hour;
    return hour >= 5 && hour < 12 ? 'Bom dia!' : (hour >= 12 && hour < 18 ? 'Boa tarde!' : 'Boa noite!');
  }

  @override
  Widget build(BuildContext context) {
    final words = app.savedWords.list;
    final due = words.due().length;
    final average = app.practice.history.averageScore;
    final stats = [
      const _GoalCard(),
      _StatCard('${words.words.length}', 'palavras salvas', Icons.bookmark_rounded, AppColors.indigo, () => app.showSection(AppSection.savedWords)),
      _StatCard('$due', 'para revisar', Icons.style_rounded, AppColors.orange, () => app.showSection(AppSection.review), highlighted: due > 0),
      _StatCard(average?.toString() ?? '–', 'média de pronúncia', Icons.graphic_eq_rounded, AppColors.violet,
          () => app.showSection(AppSection.practice)),
    ];
    final title = ScreenTitle(_greeting, subtitle: 'O que vamos assistir em inglês hoje?');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _margin(context)),
      // Side by side when there is room, otherwise the cards go under the greeting.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 920
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                title,
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [for (final card in stats) Padding(padding: const EdgeInsets.only(right: 10), child: card)]),
                ),
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: title),
                for (final card in stats) Padding(padding: const EdgeInsets.only(left: 12), child: card),
              ]),
      ),
    );
  }
}

/// The daily goal: days in a row and today's progress; tapping changes the goal.
class _GoalCard extends StatelessWidget {
  const _GoalCard();

  @override
  Widget build(BuildContext context) {
    final log = app.study.log;
    final progress = log.todayProgress();
    final streak = log.streak();
    return Tooltip(
      message: 'Sequência de dias em que você atingiu a meta. Assistir, revisar e praticar contam. Toque para mudar a meta.',
      child: PopupMenuButton<int>(
        tooltip: '',
        onSelected: (minutes) => app.study.goalMinutes = minutes,
        itemBuilder: (context) => [
          const PopupMenuItem(enabled: false, child: Text('Meta diária')),
          for (final minutes in const [5, 10, 15, 20, 30, 45, 60])
            CheckedPopupMenuItem(value: minutes, checked: minutes == app.study.goalMinutes, child: Text('$minutes min por dia')),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: progress >= 1 ? AppColors.orange.withValues(alpha: 0.6) : AppColors.stroke),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(value: progress, strokeWidth: 3.5, color: AppColors.orange, backgroundColor: Colors.white10),
                Icon(Icons.local_fire_department_rounded, size: 17, color: streak > 0 ? AppColors.orange : AppColors.textDim),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(streak == 1 ? '1 dia' : '$streak dias', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('hoje: ${app.study.todayMinutes}/${app.study.goalMinutes} min',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: progress >= 1 ? AppColors.orange : AppColors.textDim)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  const _StatCard(this.value, this.title, this.icon, this.color, this.onTap, {this.highlighted = false});
  final String value, title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHover : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.highlighted ? widget.color.withValues(alpha: 0.6) : AppColors.stroke),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconTile(widget.icon, color: widget.color, size: 32),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text(widget.title, style: const TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Side margin of the library: smaller on a phone.
double _margin(BuildContext context) => isCompact(context) ? 16 : 28;

void _play(LibraryItem item, {bool fromStart = false}) =>
    app.open(item.path, at: !fromStart && item.isInProgress ? item.position : null);

Future<void> _remove(BuildContext context, LibraryItem item) async {
  if (!item.isDownload) return app.library.forget(item);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Apagar “${item.title}”?'),
      content: Text('O ${item.isAudio ? 'arquivo' : 'vídeo'} (${formatBytes(item.size)}) e a transcrição serão apagados. '
          'As palavras salvas e o histórico de pronúncia continuam.'),
      actions: [
        GlassButton(label: 'Cancelar', onPressed: () => Navigator.pop(context, false)),
        PrimaryButton(
          label: 'Apagar',
          gradient: const LinearGradient(colors: [AppColors.red, AppColors.pink]),
          onPressed: () => Navigator.pop(context, true),
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
    final compact = isCompact(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _margin(context)),
      child: Container(
        height: compact ? 250 : 360,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.stroke),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          _Cover(item: item, showTitle: false),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xD9000000)]),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xCC000000), Color(0x33000000), Colors.transparent]),
            ),
          ),
          Positioned(
            left: compact ? 18 : 32,
            bottom: compact ? 18 : 30,
            right: compact ? 18 : 32,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TagChip(item.lastOpened == null ? 'NOVO NA BIBLIOTECA' : 'ASSISTIDO RECENTEMENTE',
                  icon: item.lastOpened == null ? Icons.auto_awesome : Icons.schedule, color: AppColors.orange),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 24 : 36, fontWeight: FontWeight.w900, height: 1.1,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 8)])),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Details(item: item),
                if (item.hasTranscript) const TagChip('Legendas prontas', icon: Icons.closed_caption, color: Colors.white),
              ]),
              if (item.isInProgress) ...[
                const SizedBox(height: 10),
                SizedBox(width: 300, child: GradientProgress(value: item.progress ?? 0, height: 5)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                PrimaryButton(label: item.isInProgress ? 'Continuar' : 'Assistir', icon: Icons.play_arrow_rounded, onPressed: () => _play(item)),
                if (item.isInProgress) ...[
                  const SizedBox(width: 10),
                  GlassButton(label: 'Do início', icon: Icons.replay_rounded, onPressed: () => _play(item, fromStart: true)),
                ],
              ]),
            ]),
          ),
        ]),
      ),
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
    final compact = isCompact(context);
    final width = compact ? 196.0 : 248.0;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 18 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _margin(context)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(title, style: TextStyle(fontSize: compact ? 17 : 19, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text('${items.length}', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700)),
          ]),
        ),
        SizedBox(
          height: width * 9 / 16 + 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: _margin(context), vertical: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => SizedBox(width: compact ? 12 : 18),
            itemBuilder: (context, index) => _Card(item: items[index], width: width),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({required this.item, required this.width});
  final LibraryItem item;
  final double width;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final width = widget.width;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _play(item),
        onSecondaryTapDown: (details) => _menu(context, details.globalPosition),
        // Phones: press and hold for the menu.
        onLongPressStart: (details) => _menu(context, details.globalPosition),
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
              width: width,
              height: width * 9 / 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _hovered ? AppColors.violet.withValues(alpha: 0.4) : Colors.black45,
                    blurRadius: _hovered ? 20 : 8,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Container(
                // Gradient ring on hover.
                padding: EdgeInsets.all(_hovered ? 2 : 1),
                decoration: BoxDecoration(
                  gradient: _hovered ? AppColors.warm : null,
                  color: _hovered ? null : AppColors.stroke,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(fit: StackFit.expand, children: [
                    _Cover(item: item, showTitle: true),
                    if (item.isInProgress)
                      Positioned(left: 10, right: 10, bottom: 10, child: GradientProgress(value: item.progress ?? 0, height: 4)),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(children: [
                        if (item.hasTranscript) const _Badge('CC', 'Legendas prontas'),
                        if (item.isAudio) const _Badge('♪', 'Música'),
                      ]),
                    ),
                    if (_hovered) ...[
                      Center(
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: AppColors.brand,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.6), blurRadius: 14)],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GlassIconButton(
                          icon: item.isDownload ? Icons.delete_outline : Icons.close,
                          size: 28,
                          tooltip: item.isDownload ? 'Apagar o vídeo baixado' : 'Remover da biblioteca (o arquivo continua no computador)',
                          onPressed: () => _remove(context, item),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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
        if (!isMobile) const PopupMenuItem(value: 'folder', child: Text('Mostrar na pasta')),
        PopupMenuItem(value: 'remove', child: Text(item.isDownload ? (isMobile ? 'Apagar do app…' : 'Apagar vídeo…') : 'Remover da biblioteca')),
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
    return Text(parts.join(' · '), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: small ? 12 : 14));
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
