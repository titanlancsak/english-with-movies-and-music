import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../core/pronunciation.dart';
import '../core/transcript.dart';
import '../services/app_controller.dart';
import '../services/paths.dart';
import '../services/recorder.dart';
import 'common.dart';

Future<void> showPracticeDialog(BuildContext context, TranscriptLine line) =>
    showDialog(context: context, builder: (_) => PracticeDialog(line: line));

/// Practice one subtitle line: listen, record, get a score.
class PracticeDialog extends StatefulWidget {
  const PracticeDialog({super.key, required this.line});
  final TranscriptLine line;

  @override
  State<PracticeDialog> createState() => _PracticeDialogState();
}

enum _Phase { idle, recording, analyzing, result, failed }

class _PracticeDialogState extends State<PracticeDialog> {
  final _recorder = VoiceRecorder();
  final _playback = Player();
  _Phase _phase = _Phase.idle;
  PronunciationResult? _result;
  String? _error, _recording;

  @override
  void dispose() {
    _recorder.dispose();
    _playback.dispose();
    _deleteRecording();
    super.dispose();
  }

  void _deleteRecording() {
    final path = _recording;
    if (path == null) return;
    for (final file in [File(path), File('${p.withoutExtension(path)}.json')]) {
      if (file.existsSync()) file.deleteSync();
    }
    _recording = null;
  }

  Future<void> _record() async {
    if (!await _recorder.hasPermission()) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Permita o acesso ao microfone nas configurações de privacidade do Windows.';
      });
      return;
    }
    app.player.pause();
    await _playback.stop();
    _deleteRecording();
    final path = p.join(AppPaths.practice.path, '${DateTime.now().millisecondsSinceEpoch}.wav');
    final seconds = (widget.line.end - widget.line.start) * 2.5 + 3;
    await _recorder.start(path, maxDuration: Duration(milliseconds: (seconds.clamp(8, 60) * 1000).round()), onFinish: _analyze);
    setState(() {
      _recording = path;
      _phase = _Phase.recording;
    });
  }

  Future<void> _analyze(String path) async {
    setState(() => _phase = _Phase.analyzing);
    try {
      final result = await app.assess(path, widget.line);
      app.practice.add(result, widget.line, app.sourceName);
      if (mounted) {
        setState(() {
          _result = result;
          _phase = _Phase.result;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
          Row(children: [
            const Text('Pratique a fala', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${app.sourceName ?? ''} · ${formatTime(widget.line.start)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(widget.line.text, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 14),
          _controls(),
          const SizedBox(height: 14),
          _content(),
          _history(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          ),
        ]),
      ),
    );
  }

  Widget _controls() {
    return ValueListenableBuilder<bool>(
      valueListenable: _recorder.isRecording,
      builder: (context, recording, _) => Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: recording ? null : () => app.playSegment(widget.line),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Ouvir o personagem'),
        ),
        if (recording) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _recorder.stop(),
            icon: const Icon(Icons.stop),
            label: const Text('Parar'),
          ),
          SizedBox(
            width: 120,
            child: ValueListenableBuilder<double>(
              valueListenable: _recorder.level,
              builder: (context, level, _) => LinearProgressIndicator(value: level, color: Colors.red),
            ),
          ),
          const Text('Fale agora…', style: TextStyle(color: Colors.white60)),
        ] else ...[
          FilledButton.icon(
            onPressed: _phase == _Phase.analyzing ? null : _record,
            icon: const Icon(Icons.mic),
            label: Text(_phase == _Phase.idle ? 'Gravar' : 'Gravar de novo'),
          ),
          if (_recording != null && _phase != _Phase.analyzing)
            OutlinedButton.icon(
              onPressed: () => _playback.open(Media(_recording!)),
              icon: const Icon(Icons.graphic_eq),
              label: const Text('Ouvir minha voz'),
            ),
        ],
      ]),
    );
  }

  Widget _content() {
    switch (_phase) {
      case _Phase.idle:
        return const Text('Ouça o personagem, clique em Gravar e repita a frase. A gravação para sozinha quando você termina de falar.',
            style: TextStyle(color: Colors.white60));
      case _Phase.recording:
        return const SizedBox.shrink();
      case _Phase.analyzing:
        return const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Analisando a sua pronúncia…'),
        ]);
      case _Phase.failed:
        return Text(_error ?? '', style: const TextStyle(color: Colors.orange));
      case _Phase.result:
        return _resultView(_result!);
    }
  }

  Widget _resultView(PronunciationResult result) {
    Color colorFor(WordStatus status) => switch (status) {
          WordStatus.correct => Colors.green,
          WordStatus.unsure => Colors.yellow,
          WordStatus.wrong => Colors.red,
          WordStatus.missing => Colors.grey,
        };
    Widget metric(String title, double value) => Row(children: [
          SizedBox(width: 100, child: Text(title)),
          SizedBox(width: 160, child: LinearProgressIndicator(value: value)),
          SizedBox(width: 40, child: Text(' ${(value * 100).round()}')),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ScoreRing(score: result.score),
        const SizedBox(width: 20),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(scoreLabel(result.score), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          metric('Precisão', result.accuracy),
          metric('Fluência', result.fluency),
          metric('Completude', result.completeness),
        ]),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final word in result.words)
          Tooltip(
            message: switch (word.status) {
              WordStatus.correct => 'Correta',
              WordStatus.unsure => word.heard == null ? 'Saiu pouco clara' : 'Parecida: entendi “${word.heard}”',
              WordStatus.wrong => 'Entendi “${word.heard ?? '?'}”',
              WordStatus.missing => 'Não foi dita',
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: colorFor(word.status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(word.text,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorFor(word.status),
                    decoration: word.status == WordStatus.missing ? TextDecoration.lineThrough : null,
                  )),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      const Text('● verde: correta   ● amarelo: pouco clara   ● vermelho: errada   ● cinza: faltou',
          style: TextStyle(fontSize: 12, color: Colors.white54)),
      if (result.recognizedText.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Entendi: “${result.recognizedText.trim()}”', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white60)),
      ],
      const SizedBox(height: 8),
      for (final tip in result.tips)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lightbulb_outline, size: 18, color: accentOrange),
            const SizedBox(width: 6),
            Expanded(child: Text(tip)),
          ]),
        ),
    ]);
  }

  Widget _history() {
    return ListenableBuilder(
      listenable: app.practice,
      builder: (context, _) {
        final record = app.practice.record(widget.line, app.sourceName);
        if (record == null) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(height: 28),
          Row(children: [
            const Text('Seu histórico nesta fala', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('Melhor nota: ${record.best} · ${record.attempts.length} tentativa${record.attempts.length == 1 ? '' : 's'}'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final attempt in record.attempts.reversed.take(12))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: scoreColor(attempt.score).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Column(children: [
                  Text('${attempt.score}', style: TextStyle(color: scoreColor(attempt.score), fontWeight: FontWeight.bold)),
                  Text(relativeTime(attempt.date), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                ]),
              ),
          ]),
        ]);
      },
    );
  }
}
