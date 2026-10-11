import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/transcript.dart';
import '../core/word_normalizer.dart';
import '../services/app_controller.dart';
import '../services/log.dart';
import 'common.dart';
import 'practice_dialog.dart';
import 'theme.dart';
import 'word_dialog.dart';

/// Video on top, live subtitles below.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build());

  Widget _build() {
    final video = Stack(fit: StackFit.expand, children: [
          ColoredBox(color: Colors.black, child: Video(controller: app.video)),
          if (app.isAudio)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.indigo.withValues(alpha: 0.6), AppColors.violet.withValues(alpha: 0.5), AppColors.orange.withValues(alpha: 0.35)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.music_note_rounded, size: 56, color: Colors.white),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(app.sourceName ?? '',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
    return LayoutBuilder(builder: (context, constraints) {
      // A phone held upright: a full-width 16:9 video on top, the subtitles take the rest.
      if (constraints.maxHeight > constraints.maxWidth && constraints.maxWidth < 700) {
        return Column(children: [
          SizedBox(height: min(constraints.maxWidth * 9 / 16, constraints.maxHeight * 0.45), child: video),
          const Expanded(child: TranscriptPanel()),
        ]);
      }
      // Computer: the video in a rounded card with a glow, the subtitles in a glass panel.
      final videoHeight = min(constraints.maxWidth * 9 / 16, constraints.maxHeight * 0.56);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(children: [
          Center(
            child: Container(
              width: videoHeight * 16 / 9,
              height: videoHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.stroke),
                boxShadow: [BoxShadow(color: AppColors.indigo.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 10))],
              ),
              clipBehavior: Clip.antiAlias,
              child: video,
            ),
          ),
          const SizedBox(height: 14),
          const Expanded(child: GlassCard(radius: 18, child: TranscriptPanel())),
        ]),
      );
    });
  }
}

class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({super.key});

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final _scroll = ItemScrollController();
  StreamSubscription<int>? _jumps;
  Object? _loggedTranscript;

  @override
  void initState() {
    super.initState();
    app.activeLine.addListener(_followLine);
    _jumps = app.scrollRequests.stream.listen((line) {
      if (_scroll.isAttached) _scroll.jumpTo(index: line, alignment: 0.35);
    });
  }

  @override
  void dispose() {
    app.activeLine.removeListener(_followLine);
    _jumps?.cancel();
    super.dispose();
  }

  void _followLine() {
    final line = app.activeLine.value;
    if (line == null || !app.follow.value || !_scroll.isAttached) return;
    _scroll.scrollTo(index: line, alignment: 0.35, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  /// Rebuilds when the transcript arrives (the list inside also follows the active line).
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final transcript = app.transcript;
    if (transcript == null) {
      return const EmptyState(
          icon: Icons.subtitles_rounded,
          title: 'Preparando a legenda',
          text: 'A legenda aparece aqui assim que a transcrição terminar.\nVocê já pode assistir enquanto isso.');
    }
    if (transcript.lines.isEmpty) {
      return const EmptyState(icon: Icons.speaker_notes_off_rounded, title: 'Nenhuma fala encontrada', text: 'Este arquivo não tem falas em inglês reconhecíveis.');
    }
    if (!identical(_loggedTranscript, transcript)) {
      _loggedTranscript = transcript;
      log('Legenda na tela: ${transcript.lines.length} falas');
    }
    return Stack(children: [
      NotificationListener<UserScrollNotification>(
        // The user is reading: stop following until the video jumps or they press the button.
        onNotification: (notification) {
          if (notification.direction != ScrollDirection.idle) app.follow.value = false;
          return false;
        },
        child: ListenableBuilder(
          listenable: Listenable.merge([app.activeLine, app.activeWord, app.savedWords, app.practice, app]),
          builder: (context, _) => ScrollablePositionedList.builder(
            itemScrollController: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 14),
            itemCount: transcript.lines.length,
            itemBuilder: (context, index) {
              final isActive = index == app.activeLine.value;
              return LineRow(line: transcript.lines[index], isActive: isActive, activeWord: isActive ? app.activeWord.value : null);
            },
          ),
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: app.follow,
        builder: (context, follow, _) => follow
            ? const SizedBox.shrink()
            : Positioned(
                right: 16,
                bottom: 16,
                child: PrimaryButton(
                  onPressed: () {
                    app.follow.value = true;
                    final line = app.activeLine.value;
                    if (line != null) _scroll.jumpTo(index: line, alignment: 0.35);
                  },
                  icon: Icons.my_location,
                  label: 'Voltar para a fala atual',
                ),
              ),
      ),
    ]);
  }
}

class LineRow extends StatefulWidget {
  const LineRow({super.key, required this.line, required this.isActive, this.activeWord});
  final TranscriptLine line;
  final bool isActive;
  final int? activeWord;

  @override
  State<LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<LineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final isActive = widget.isActive;
    final activeWord = widget.activeWord;
    final best = app.practice.record(line, app.sourceName)?.best;
    final compact = isCompact(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 1),
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: isActive ? 14 : 6),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(colors: [AppColors.indigo.withValues(alpha: 0.22), AppColors.violet.withValues(alpha: 0.12)])
              : null,
          color: isActive ? null : (_hovered ? AppColors.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundDecoration: isActive ? const _AccentBar() : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: compact ? 58 : 70,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              InkWell(
                onTap: () => app.seek(line.start),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(formatTime(line.start),
                      style: TextStyle(color: isActive ? AppColors.violet : AppColors.textDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (best != null) ...[TagChip('$best', color: scoreColor(best)), const SizedBox(width: 4)],
                if (isActive || _hovered || isMobile)
                  GlassIconButton(
                    icon: Icons.mic_rounded,
                    size: 26,
                    color: isActive ? AppColors.violet : Colors.white,
                    tooltip: 'Praticar a pronúncia desta fala',
                    onPressed: () {
                      app.player.pause();
                      showPracticeDialog(context, line);
                    },
                  ),
              ]),
            ]),
          ),
          SizedBox(width: compact ? 8 : 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 4, runSpacing: 6, children: [
                for (var i = 0; i < line.words.length; i++)
                  _Word(
                    word: line.words[i],
                    line: line,
                    isLineActive: isActive,
                    isSpoken: isActive && activeWord != null && i <= activeWord,
                    isCurrent: isActive && activeWord == i,
                  ),
              ]),
              if (isActive && app.showTranslation) _ActiveTranslation(text: line.text),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({required this.word, required this.line, required this.isLineActive, required this.isSpoken, required this.isCurrent});
  final TimedWord word;
  final TranscriptLine line;
  final bool isLineActive, isSpoken, isCurrent;

  @override
  Widget build(BuildContext context) {
    final saved = app.savedWords.contains(word.text);
    final color = !isLineActive
        ? Colors.white.withValues(alpha: 0.6)
        : isSpoken
            ? Colors.white
            : Colors.white.withValues(alpha: 0.42);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (lookupKey(word.text).isEmpty) return;
          app.player.pause();
          showWordDialog(context, word.text, line);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: isCurrent ? 7 : 2, vertical: isCurrent ? 1 : 0),
          decoration: BoxDecoration(
            gradient: isCurrent ? AppColors.brand : null,
            borderRadius: BorderRadius.circular(99),
            boxShadow: isCurrent ? [BoxShadow(color: AppColors.violet.withValues(alpha: 0.6), blurRadius: 10)] : null,
          ),
          child: Text(
            word.text,
            style: TextStyle(
              fontSize: isCompact(context) ? (isLineActive ? 20 : 15) : (isLineActive ? 22 : 16),
              fontWeight: isLineActive ? FontWeight.w800 : FontWeight.normal,
              color: color,
              decoration: saved ? TextDecoration.underline : null,
              decorationColor: accentOrange,
              decorationThickness: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Portuguese translation of the line being spoken (only the active line, to stay within the free quota).
class _ActiveTranslation extends StatelessWidget {
  const _ActiveTranslation({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      key: ValueKey(text),
      future: app.translator.translate(text),
      initialData: app.translator.cached(text),
      builder: (context, snapshot) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          snapshot.data ?? app.translator.problem ?? 'traduzindo…',
          style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.orange, fontSize: 15),
        ),
      ),
    );
  }
}

/// The gradient bar on the left of the line being spoken.
class _AccentBar extends Decoration {
  const _AccentBar();

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _AccentBarPainter();
}

class _AccentBarPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = Rect.fromLTWH(offset.dx, offset.dy + 12, 3, size.height - 24);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()
      ..shader = LinearGradient(colors: AppColors.warm.colors, begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect));
  }
}
