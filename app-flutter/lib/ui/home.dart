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
import 'settings_dialog.dart';
import 'theme.dart';

/// The app shell: a sidebar on a computer, a bottom bar on a phone, and the current screen.
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
      listenable: Listenable.merge([app, app.library, app.savedWords, app.practice]),
      builder: (context, _) => PopScope(
        // Android back button: back to the library first.
        canPop: app.section == AppSection.library,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) app.showSection(AppSection.library);
        },
        child: isCompact(context) ? _phone(context) : _desktop(context),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _Sidebar(),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: AuroraBackground()),
                SafeArea(
                  left: false,
                  child: Column(
                    children: [
                      _TopBar(actions: _actions(context)),
                      _banner(),
                      const StatusBar(),
                      Expanded(child: _withDrop(_content())),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(BuildContext context) {
    final sections = [
      (AppSection.library, Icons.grid_view_rounded, 'Biblioteca'),
      if (app.mediaPath != null) (AppSection.player, app.isAudio ? Icons.music_note : Icons.play_circle_fill, 'Assistindo'),
      (AppSection.savedWords, Icons.bookmark_rounded, 'Palavras'),
      (AppSection.review, Icons.style_rounded, 'Revisão'),
      (AppSection.practice, Icons.graphic_eq_rounded, 'Pronúncia'),
    ];
    final selected = sections.indexWhere((s) => s.$1 == app.section);
    final due = app.savedWords.list.due().length;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(actions: _actions(context)),
                _banner(),
                const StatusBar(),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF101018),
        indicatorColor: AppColors.violet.withValues(alpha: 0.3),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (index) => app.showSection(sections[index].$1),
        destinations: [
          for (final s in sections)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: s.$1 == AppSection.review && due > 0,
                label: Text('$due'),
                backgroundColor: AppColors.orange,
                child: Icon(s.$2),
              ),
              label: s.$3,
            ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (app.section) {
      case AppSection.player when app.mediaPath != null:
        return const PlayerScreen();
      case AppSection.savedWords:
        return const SavedWordsScreen();
      case AppSection.review:
        return const ReviewScreen();
      case AppSection.practice:
        return const PracticeHistoryScreen();
      default:
        return app.library.items.isEmpty ? DropZone(dragging: _dragging) : const LibraryScreen();
    }
  }

  Widget _banner() => Column(children: [_updateBanner(), _toolsBanner()]);

  /// "Nova versão disponível" when GitHub has a newer release.
  Widget _updateBanner() {
    if (app.updates.available == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GlassCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.violet),
          const SizedBox(width: 10),
          Expanded(child: Text('Nova versão ${app.updates.availableVersion} disponível', style: const TextStyle(fontWeight: FontWeight.w700))),
          GlassButton(label: 'Depois', onPressed: app.updates.dismiss),
          const SizedBox(width: 8),
          PrimaryButton(label: 'Baixar', icon: Icons.download_rounded, onPressed: app.updates.download),
        ]),
      ),
    );
  }

  Widget _toolsBanner() => _missingTools.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: GlassCard(
            color: AppColors.orange.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(child: Text('Faltam programas: ${_missingTools.join(', ')}. Baixe o app completo na página de Releases do GitHub.')),
              ],
            ),
          ),
        );

  Widget _withDrop(Widget child) {
    if (isMobile) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) unawaited(app.open(details.files.first.path));
      },
      child: child,
    );
  }

  /// Buttons at the top right, depending on the screen.
  List<Widget> _actions(BuildContext context) {
    final compact = isCompact(context);
    if (app.section == AppSection.player && app.mediaPath != null) {
      return [
        GlassIconButton(
          icon: Icons.translate,
          tooltip: 'Mostrar a tradução da fala atual',
          color: app.showTranslation ? AppColors.violet : Colors.white,
          onPressed: () => app.setShowTranslation(!app.showTranslation),
        ),
        GlassIconButton(icon: Icons.closed_caption_outlined, tooltip: 'Importar legenda (.srt)', onPressed: _importSrt),
        GlassIconButton(icon: Icons.refresh, tooltip: 'Transcrever de novo', onPressed: app.retranscribe),
        GlassIconButton(icon: Icons.close, tooltip: 'Fechar e voltar para a biblioteca', onPressed: app.closeMedia),
      ];
    }
    if (app.section == AppSection.library) {
      return [
        if (compact) GlassIconButton(icon: Icons.settings_rounded, tooltip: 'Ajustes', onPressed: () => showSettings(context)),
        if (!isMobile) GlassButton(label: 'YouTube', icon: Icons.link, onPressed: () => showLinkDialog(context)),
        compact
            ? GlassIconButton(icon: Icons.add, tooltip: 'Abrir arquivo', onPressed: openMediaFile)
            : PrimaryButton(label: 'Abrir arquivo', icon: Icons.add, onPressed: openMediaFile),
      ];
    }
    return const [];
  }

  Future<void> _importSrt() async {
    // Phones do not know a MIME type for .srt, so any file can be chosen there.
    final path = (await FilePicker.pickFile(type: isMobile ? FileType.any : FileType.custom, allowedExtensions: isMobile ? null : ['srt']))?.path;
    if (path != null) app.importSubtitles(path);
  }
}

/// Title of the current screen and its buttons.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final title = switch (app.section) {
      AppSection.player => app.sourceName ?? 'Assistindo',
      // These screens show a big title of their own; a phone does not repeat it above.
      AppSection.savedWords => compact ? '' : 'Palavras salvas',
      AppSection.review => compact ? '' : 'Revisão',
      AppSection.practice => compact ? '' : 'Pronúncia',
      AppSection.library => compact ? 'English with Movies' : 'Biblioteca',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 12 : 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 17 : 14,
                fontWeight: compact ? FontWeight.w800 : FontWeight.w600,
                color: compact ? Colors.white : AppColors.textDim,
              ),
            ),
          ),
          for (final action in actions) Padding(padding: const EdgeInsets.only(left: 8), child: action),
        ],
      ),
    );
  }
}

/// Navigation on the left: library, the open film, saved words, review and pronunciation.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  // Listens itself: as a const widget it would not be rebuilt when the shell rebuilds.
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([app, app.savedWords, app.practice]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final words = app.savedWords.list;
    final average = app.practice.history.averageScore;
    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: Color(0xFF101018),
        border: Border(right: BorderSide(color: AppColors.stroke)),
      ),
      // Scrolls when the window is short; otherwise the transcription card sits at the bottom.
      child: SafeArea(
        right: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: AppColors.brand,
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.5), blurRadius: 14)],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('English', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                              Text(
                                'with Movies & Music',
                                style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Padding(padding: EdgeInsets.only(left: 10, bottom: 4), child: SectionLabel('Assistir')),
                    _SidebarItem(section: AppSection.library, icon: Icons.grid_view_rounded, title: 'Biblioteca'),
                    if (app.mediaPath != null)
                      _SidebarItem(
                        section: AppSection.player,
                        icon: app.isAudio ? Icons.music_note_rounded : Icons.play_circle_fill_rounded,
                        title: app.sourceName ?? '',
                        subtitle: 'Assistindo agora',
                      ),
                    const Padding(padding: EdgeInsets.only(left: 10, top: 18, bottom: 4), child: SectionLabel('Aprender')),
                    _SidebarItem(section: AppSection.savedWords, icon: Icons.bookmark_rounded, title: 'Palavras salvas', badge: words.words.length),
                    _SidebarItem(
                      section: AppSection.review,
                      icon: Icons.style_rounded,
                      title: 'Revisão',
                      badge: words.due().length,
                      badgeColor: AppColors.orange,
                    ),
                    _SidebarItem(section: AppSection.practice, icon: Icons.graphic_eq_rounded, title: 'Pronúncia', badge: average),
                    const Spacer(),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => showSettings(context),
                      child: GlassCard(
                        radius: 12,
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          const Icon(Icons.settings_rounded, size: 18, color: AppColors.textDim),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Ajustes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              Text(app.sync.folder == null ? app.model.title : 'Sincronização ligada',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({required this.section, required this.icon, required this.title, this.subtitle, this.badge, this.badgeColor});
  final AppSection section;
  final IconData icon;
  final String title;
  final String? subtitle;
  final int? badge;
  final Color? badgeColor;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = app.section == widget.section;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => app.showSection(widget.section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.09) : (_hovered ? Colors.white.withValues(alpha: 0.04) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.brand : null,
                  color: selected ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 16, color: selected ? Colors.white : AppColors.textDim),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.orange, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              if (widget.badge != null && widget.badge! > 0)
                Text(
                  '${widget.badge}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: widget.badgeColor ?? AppColors.textDim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which Whisper model transcribes.
Future<void> chooseModel(BuildContext context) async {
  final chosen = await showDialog<WhisperModel>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Qualidade da transcrição'),
      children: [
        for (final m in WhisperModel.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, m),
            child: Row(
              children: [
                Icon(
                  m == app.model ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20,
                  color: m == app.model ? AppColors.violet : AppColors.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(m.title)),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            'Os modelos maiores são mais precisos e mais lentos (no celular, bem mais lentos).',
            style: TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        ),
      ],
    ),
  );
  if (chosen != null) app.setModel(chosen);
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
            const Text(
              'Cole o link do vídeo. Ele é baixado, transcrito e fica salvo na sua biblioteca (Vídeos › English with Movies).',
              style: TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=…',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.stroke),
                ),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
      actions: [
        GlassButton(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
        PrimaryButton(label: 'Baixar', icon: Icons.download, onPressed: () => Navigator.pop(context, controller.text)),
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
    final margin = EdgeInsets.fromLTRB(isCompact(context) ? 12 : 20, 8, isCompact(context) ? 12 : 20, 4);
    switch (app.status) {
      case Status.working:
        final progress = app.progress;
        return Padding(
          padding: margin,
          child: GlassCard(
            radius: 14,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(app.message, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (progress != null) Text('${(progress * 100).round()}%', style: const TextStyle(color: AppColors.textDim)),
                        ],
                      ),
                      if (progress != null) ...[const SizedBox(height: 8), GradientProgress(value: progress)],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GlassButton(label: 'Cancelar', onPressed: app.cancel),
              ],
            ),
          ),
        );
      case Status.failed:
        return Padding(
          padding: margin,
          child: GlassCard(
            radius: 14,
            color: AppColors.orange.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(app.message)),
                if (app.mediaPath != null) GlassButton(label: 'Tentar de novo', onPressed: app.retranscribe),
              ],
            ),
          ),
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
    final compact = isCompact(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.all(compact ? 16 : 28),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dragging ? AppColors.violet.withValues(alpha: 0.08) : Colors.transparent,
        border: Border.all(color: dragging ? AppColors.violet : Colors.white24, width: 1.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: AppColors.brand,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.6), blurRadius: 40)],
                ),
                child: const Icon(Icons.movie_filter_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 22),
              GradientText(
                'Aprenda inglês com o que você ama assistir',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: compact ? 24 : 30, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                isMobile
                    ? 'Escolha um filme ou uma música do celular. O app transcreve as falas, mostra a legenda em tempo real e explica qualquer palavra em que você tocar.'
                    : 'Arraste um filme ou uma música para cá. O app transcreve as falas, mostra a legenda\nem tempo real e explica qualquer palavra em que você clicar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  PrimaryButton(label: 'Escolher arquivo…', icon: Icons.folder_rounded, onPressed: openMediaFile),
                  if (!isMobile) GlassButton(label: 'Baixar do YouTube…', icon: Icons.link, onPressed: () => showLinkDialog(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
