import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../core/phonemes.dart';
import '../core/pronunciation.dart';
import '../core/transcript.dart';
import '../services/app_controller.dart';
import '../services/paths.dart';
import '../services/recorder.dart';
import 'common.dart';
import 'theme.dart';

Future<void> showPracticeDialog(BuildContext context, TranscriptLine line) => showDialog(
  context: context,
  builder: (_) => PracticeDialog(line: line),
);

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
    await _recorder.start(
      path,
      maxDuration: Duration(milliseconds: (seconds.clamp(8, 60) * 1000).round()),
      onFinish: _analyze,
    );
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
      clipBehavior: Clip.antiAlias,
      insetPadding: isCompact(context) ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
        child: Stack(
          children: [
            const Positioned.fill(child: AuroraBackground()),
            ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(22),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionLabel('Treino de pronúncia'),
                          SizedBox(height: 2),
                          GradientText('Pratique a fala', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    if (!isCompact(context))
                      Flexible(
                        child: TagChip(
                          '${app.sourceName ?? ''} · ${formatTime(widget.line.start)}',
                          icon: Icons.movie_rounded,
                          color: AppColors.textDim,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.indigo.withValues(alpha: 0.25), AppColors.violet.withValues(alpha: 0.12)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: SelectableText(widget.line.text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                _controls(),
                const SizedBox(height: 14),
                _content(),
                // The sound analysis needs the Windows/Mac phoneme recognizer; phones do not have it yet.
                if (!isMobile) const _SoundsSetupCard(),
                _history(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassButton(label: 'Fechar', onPressed: () => Navigator.pop(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return ValueListenableBuilder<bool>(
      valueListenable: _recorder.isRecording,
      builder: (context, recording, _) => Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GlassButton(onPressed: recording ? null : () => app.playSegment(widget.line), icon: Icons.play_arrow_rounded, label: 'Ouvir o personagem'),
          if (recording) ...[
            PrimaryButton(
              gradient: const LinearGradient(colors: [AppColors.red, AppColors.pink]),
              onPressed: () => _recorder.stop(),
              icon: Icons.stop_rounded,
              label: 'Parar',
            ),
            SizedBox(
              width: 120,
              child: ValueListenableBuilder<double>(
                valueListenable: _recorder.level,
                builder: (context, level, _) => GradientProgress(value: level, height: 8),
              ),
            ),
            const Text('Fale agora…', style: TextStyle(color: AppColors.textDim)),
          ] else ...[
            PrimaryButton(
              onPressed: _phase == _Phase.analyzing ? null : _record,
              icon: Icons.mic_rounded,
              label: _phase == _Phase.idle ? 'Gravar' : 'Gravar de novo',
            ),
            if (_recording != null && _phase != _Phase.analyzing)
              GlassButton(onPressed: () => _playback.open(Media(_recording!)), icon: Icons.graphic_eq_rounded, label: 'Ouvir minha voz'),
          ],
        ],
      ),
    );
  }

  Widget _content() {
    switch (_phase) {
      case _Phase.idle:
        return Text(
          'Ouça o personagem, ${isMobile ? 'toque' : 'clique'} em Gravar e repita a frase. A gravação para sozinha quando você termina de falar.',
          style: const TextStyle(color: AppColors.textDim),
        );
      case _Phase.recording:
        return const SizedBox.shrink();
      case _Phase.analyzing:
        return const Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet)),
            SizedBox(width: 10),
            Text('Analisando a sua pronúncia…'),
          ],
        );
      case _Phase.failed:
        return Text(_error ?? '', style: const TextStyle(color: Colors.orange));
      case _Phase.result:
        return _resultView(_result!);
    }
  }

  Widget _resultView(PronunciationResult result) {
    Color colorFor(WordStatus status) => switch (status) {
      WordStatus.correct => AppColors.green,
      WordStatus.unsure => AppColors.yellow,
      WordStatus.wrong => AppColors.red,
      WordStatus.missing => Colors.grey,
    };
    Widget metric(String title, double value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 92,
            child: Text(title, style: const TextStyle(color: AppColors.textDim)),
          ),
          SizedBox(width: 130, child: GradientProgress(value: value)),
          SizedBox(
            width: 40,
            child: Text(' ${(value * 100).round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Side by side; on a phone the metrics go under the score.
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ScoreRing(score: result.score, size: 104),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scoreLabel(result.score), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  metric('Precisão', result.accuracy),
                  metric('Fluência', result.fluency),
                  metric('Completude', result.completeness),
                  if (result.sounds != null) metric('Sons', result.sounds!.score),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final word in result.words)
              Tooltip(
                message: switch (word.status) {
                  WordStatus.correct => 'Correta',
                  WordStatus.unsure => word.heard == null ? 'Saiu pouco clara' : 'Parecida: entendi “${word.heard}”',
                  WordStatus.wrong => 'Entendi “${word.heard ?? '?'}”',
                  WordStatus.missing => 'Não foi dita',
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorFor(word.status).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: colorFor(word.status).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    word.text,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorFor(word.status),
                      decoration: word.status == WordStatus.missing ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '● verde: correta   ● amarelo: pouco clara   ● vermelho: errada   ● cinza: faltou',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        if (result.recognizedText.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Entendi: “${result.recognizedText.trim()}”',
            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white60),
          ),
        ],
        const SizedBox(height: 8),
        for (final tip in result.tips)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_rounded, size: 18, color: AppColors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text(tip)),
              ],
            ),
          ),
        if (result.sounds != null) _SoundsSection(sounds: result.sounds!),
      ],
    );
  }

  Widget _history() {
    return ListenableBuilder(
      listenable: app.practice,
      builder: (context, _) {
        final record = app.practice.record(widget.line, app.sourceName);
        if (record == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 28),
            Row(
              children: [
                const Text('Seu histórico nesta fala', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Melhor nota: ${record.best} · ${record.attempts.length} tentativa${record.attempts.length == 1 ? '' : 's'}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attempt in record.attempts.reversed.take(12))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: scoreColor(attempt.score).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      children: [
                        Text(
                          '${attempt.score}',
                          style: TextStyle(color: scoreColor(attempt.score), fontWeight: FontWeight.bold),
                        ),
                        Text(relativeTime(attempt.date), style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Sound-by-sound feedback: each word's expected sounds, colored by how they came out.
class _SoundsSection extends StatelessWidget {
  const _SoundsSection({required this.sounds});
  final SoundAnalysis sounds;

  @override
  Widget build(BuildContext context) {
    final problems = sounds.words.where((w) => w.extra.isNotEmpty || w.sounds.any((s) => s.status != SoundStatus.correct));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sons', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (problems.isEmpty)
            const Row(
              children: [
                Icon(Icons.verified, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text('Todos os sons saíram corretos!', style: TextStyle(color: Colors.green)),
              ],
            )
          else
            for (final word in problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(word.text, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final sound in word.sounds) _SoundChip(sound: sound),
                          for (final extra in word.extra)
                            Tooltip(
                              message: 'Som a mais: /$extra/',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
                                child: Text(
                                  '+$extra',
                                  style: const TextStyle(fontFamily: 'Consolas', color: Colors.purpleAccent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          for (final tip in sounds.tips)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.record_voice_over_outlined, size: 18, color: accentOrange),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tip)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SoundChip extends StatelessWidget {
  const _SoundChip({required this.sound});
  final Sound sound;

  @override
  Widget build(BuildContext context) {
    final color = switch (sound.status) {
      SoundStatus.correct => Colors.green,
      SoundStatus.close => Colors.yellow,
      SoundStatus.wrong => Colors.red,
      SoundStatus.missing => Colors.grey,
    };
    final name = PhonemeTips.name(sound.expected);
    final title = '/${sound.expected}/${name == null ? '' : ' — $name'}';
    return Tooltip(
      message: switch (sound.status) {
        SoundStatus.correct => '$title: correto',
        SoundStatus.close => '$title: saiu parecido com /${sound.heard ?? '?'}/',
        SoundStatus.wrong => '$title: você disse /${sound.heard ?? '?'}/',
        SoundStatus.missing => '$title: não foi pronunciado',
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(5)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sound.expected,
              style: TextStyle(
                fontFamily: 'Consolas',
                color: color,
                decoration: sound.status == SoundStatus.missing ? TextDecoration.lineThrough : null,
              ),
            ),
            if (sound.heard != null)
              Text(
                sound.heard!,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 10, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }
}

/// Offers the one-time download of the sound analysis.
class _SoundsSetupCard extends StatelessWidget {
  const _SoundsSetupCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.soundSetup,
      builder: (context, _) {
        final setup = app.soundSetup;
        if (setup.isReady) return const SizedBox.shrink();
        final progress = setup.progress;
        return Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.record_voice_over_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('Análise por som', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              if (setup.problem != null)
                Text(setup.problem!, style: const TextStyle(color: Colors.orange))
              else if (progress != null) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text('Baixando o modelo de sons… ${(progress * 100).round()}%'),
                const Text('Pode continuar praticando enquanto isso.', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ] else ...[
                const Text(
                  'Descubra exatamente qual som saiu errado (o “th”, o R americano, “ship” × “sheep”…). '
                  'Instalação única: baixa cerca de 320 MB.',
                  style: TextStyle(color: Colors.white60),
                ),
                if (setup.error != null) ...[const SizedBox(height: 6), Text(setup.error!, style: const TextStyle(color: Colors.orange))],
                const SizedBox(height: 8),
                FilledButton.tonal(onPressed: setup.install, child: Text(setup.error == null ? 'Ativar análise por som' : 'Tentar de novo')),
              ],
            ],
          ),
        );
      },
    );
  }
}
