import 'dart:async';

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
import 'word_dialog.dart';

/// Video on top, live subtitles below.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build());

  Widget _build() {
    return Column(children: [
      Expanded(
        flex: 5,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: Colors.black, child: Video(controller: app.video)),
          if (app.isAudio)
            IgnorePointer(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.music_note, size: 56, color: Colors.white70),
                  Text(app.sourceName ?? '', style: const TextStyle(fontSize: 18, color: Colors.white70)),
                ]),
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
      const Expanded(flex: 4, child: TranscriptPanel()),
    ]);
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
      return const Center(
        child: Text('A legenda aparece aqui assim que a transcrição terminar.\nVocê já pode assistir enquanto isso.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
      );
    }
    if (transcript.lines.isEmpty) {
      return const Center(child: Text('Nenhuma fala encontrada neste arquivo.', style: TextStyle(color: Colors.white54)));
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
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                child: FilledButton.icon(
                  onPressed: () {
                    app.follow.value = true;
                    final line = app.activeLine.value;
                    if (line != null) _scroll.jumpTo(index: line, alignment: 0.35);
                  },
                  icon: const Icon(Icons.my_location),
                  label: const Text('Voltar para a fala atual'),
                ),
              ),
      ),
    ]);
  }
}

class LineRow extends StatelessWidget {
  const LineRow({super.key, required this.line, required this.isActive, this.activeWord});
  final TranscriptLine line;
  final bool isActive;
  final int? activeWord;

  @override
  Widget build(BuildContext context) {
    final best = app.practice.record(line, app.sourceName)?.best;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isActive ? 10 : 4),
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 70,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            InkWell(
              onTap: () => app.seek(line.start),
              child: Text(formatTime(line.start), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (best != null)
                Tooltip(
                  message: 'Sua melhor nota nesta fala',
                  child: Text('$best', style: TextStyle(color: scoreColor(best), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Praticar a pronúncia desta fala',
                icon: Icon(Icons.mic_none, color: isActive ? Theme.of(context).colorScheme.primary : Colors.white38),
                onPressed: () {
                  app.player.pause();
                  showPracticeDialog(context, line);
                },
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 5, runSpacing: 4, children: [
              for (var i = 0; i < line.words.length; i++)
                _Word(
                  word: line.words[i],
                  line: line,
                  isLineActive: isActive,
                  isSpoken: isActive && activeWord != null && i <= activeWord!,
                  isCurrent: isActive && activeWord == i,
                ),
            ]),
            if (isActive && app.showTranslation) _ActiveTranslation(text: line.text),
          ]),
        ),
      ]),
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
        ? Colors.white60
        : isSpoken
            ? Colors.white
            : Colors.white.withValues(alpha: 0.55);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (lookupKey(word.text).isEmpty) return;
          app.player.pause();
          showWordDialog(context, word.text, line);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isCurrent ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            word.text,
            style: TextStyle(
              fontSize: isLineActive ? 21 : 16,
              fontWeight: isLineActive ? FontWeight.bold : FontWeight.normal,
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
          style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70, fontSize: 15),
        ),
      ),
    );
  }
}
