import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/review.dart';
import '../core/saved_words.dart';
import '../core/word_normalizer.dart';
import '../services/app_controller.dart';
import 'common.dart';

enum ReviewMode {
  englishToPortuguese('Inglês → Português'),
  portugueseToEnglish('Português → Inglês'),
  listening('Ouvir');

  const ReviewMode(this.title);
  final String title;
}

/// Flashcard review of the saved words, with spaced repetition.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const _sessionLimit = 20;

  ReviewMode _mode = ReviewMode.englishToPortuguese;
  List<String> _queue = [];
  int _sessionSize = 0, _reviewed = 0, _remembered = 0;
  bool _flipped = false, _running = false;

  @override
  void initState() {
    super.initState();
    _start(all: false);
  }

  SavedWord? get _current =>
      _queue.isEmpty ? null : app.savedWords.list.words.where((w) => w.key == _queue.first).firstOrNull;

  void _start({required bool all}) {
    final words = [...(all ? app.savedWords.list.words : app.savedWords.list.due())]..shuffle();
    setState(() {
      _queue = words.take(_sessionLimit).map((w) => w.key).toList();
      _sessionSize = _queue.length;
      _reviewed = 0;
      _remembered = 0;
      _flipped = false;
      _running = _queue.isNotEmpty;
    });
    _speakIfListening();
  }

  void _answer(ReviewGrade grade) {
    final key = _queue.first;
    app.savedWords.grade(key, grade);
    setState(() {
      _reviewed++;
      if (grade != ReviewGrade.again) _remembered++;
      _queue.removeAt(0);
      // A forgotten word comes back at the end of this session.
      if (grade == ReviewGrade.again) _queue.add(key);
      _flipped = false;
    });
    _speakIfListening();
  }

  void _speakIfListening() {
    final word = _current;
    if (_mode == ReviewMode.listening && word != null) app.speaker.say(word.word);
  }

  @override
  Widget build(BuildContext context) {
    final word = _current;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (word != null && !_flipped) setState(() => _flipped = true);
        },
        for (final grade in ReviewGrade.values)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + grade.index)): () {
            if (word != null && _flipped) _answer(grade);
          },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('Revisão de palavras')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  SegmentedButton<ReviewMode>(
                    segments: [for (final m in ReviewMode.values) ButtonSegment(value: m, label: Text(m.title))],
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _mode = selection.first;
                        _flipped = false;
                      });
                      _speakIfListening();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_running && word != null) ...[
                    _progress(),
                    const SizedBox(height: 16),
                    Expanded(child: _card(word)),
                    const SizedBox(height: 16),
                    _buttons(word),
                  ] else if (_running)
                    Expanded(child: _finished())
                  else
                    Expanded(child: _empty()),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    final done = _sessionSize - _queue.toSet().length;
    return Column(children: [
      LinearProgressIndicator(value: _sessionSize == 0 ? 0 : done / _sessionSize),
      const SizedBox(height: 4),
      Text('$done de $_sessionSize palavras', style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }

  Widget _card(SavedWord word) {
    return GestureDetector(
      onTap: () => setState(() => _flipped = !_flipped),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _flipped ? 1 : 0),
        duration: const Duration(milliseconds: 350),
        builder: (context, value, _) {
          final showBack = value > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(pi * value),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(showBack ? pi : 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(child: SingleChildScrollView(child: showBack ? _back(word) : _front(word))),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _speak(SavedWord word) =>
      IconButton(icon: const Icon(Icons.volume_up), tooltip: 'Ouvir a pronúncia', onPressed: () => app.speaker.say(word.word));

  Widget _front(SavedWord word) {
    switch (_mode) {
      case ReviewMode.englishToPortuguese:
        return Column(children: [
          Text(word.word, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
          if (word.phonetic != null) Text(word.phonetic!, style: const TextStyle(color: Colors.white54)),
          _speak(word),
          if (word.context != null) ...[
            const SizedBox(height: 8),
            _highlighted(word.context!, word, const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.white70)),
          ],
          const SizedBox(height: 16),
          const Text('O que significa?', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
        ]);
      case ReviewMode.portugueseToEnglish:
        return Column(children: [
          Text(word.translation ?? word.definition ?? '?',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
          if (word.translation != null && word.definition != null) ...[
            const SizedBox(height: 8),
            Text(word.definition!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          ],
          const SizedBox(height: 16),
          const Text('Como se diz em inglês?', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
        ]);
      case ReviewMode.listening:
        return Column(children: [
          IconButton(iconSize: 64, icon: const Icon(Icons.volume_up), tooltip: 'Ouvir de novo', onPressed: () => app.speaker.say(word.word)),
          const SizedBox(height: 12),
          const Text('Que palavra é essa? O que significa?', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
        ]);
    }
  }

  Widget _back(SavedWord word) {
    final source = word.sourcePath;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(word.word, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
        if (word.phonetic != null) Text('  ${word.phonetic}', style: const TextStyle(color: Colors.white54)),
        _speak(word),
      ]),
      if (word.translation != null)
        Text(word.translation!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: accentOrange)),
      if (word.definition != null) ...[
        const SizedBox(height: 8),
        if (word.partOfSpeech != null)
          Text(word.partOfSpeech!, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white54, fontSize: 12)),
        Text(word.definition!, textAlign: TextAlign.center),
      ],
      if (word.context != null) ...[
        const Divider(height: 24),
        _highlighted(word.context!, word, const TextStyle(fontStyle: FontStyle.italic)),
        if (source != null && File(source).existsSync())
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              app.open(source, at: word.sourceTime ?? 0);
            },
            icon: const Icon(Icons.movie, size: 18),
            label: Text('Ver no ${word.sourceName ?? 'filme'}'),
          ),
      ],
    ]);
  }

  /// The sentence with the word in bold.
  Widget _highlighted(String sentence, SavedWord word, TextStyle style) {
    final tokens = sentence.split(' ');
    return Text.rich(
      TextSpan(style: style, children: [
        for (var i = 0; i < tokens.length; i++)
          TextSpan(
            text: (i > 0 ? ' ' : '') + tokens[i],
            style: lookupKey(tokens[i]) == word.key ? const TextStyle(fontWeight: FontWeight.bold, color: Colors.white) : null,
          ),
      ]),
      textAlign: TextAlign.center,
    );
  }

  Widget _buttons(SavedWord word) {
    if (!_flipped) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: () => setState(() => _flipped = true),
          child: const Text('Mostrar resposta  (espaço)', style: TextStyle(fontSize: 16)),
        ),
      );
    }
    const colors = [Colors.red, Colors.orange, Colors.green, Colors.blue];
    return Row(children: [
      for (final grade in ReviewGrade.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors[grade.index], padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () => _answer(grade),
              child: Column(children: [
                Text('${grade.title}  (${grade.index + 1})', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(describeNextReview(word.review, grade, DateTime.now()), style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _stats() {
    final list = app.savedWords.list;
    final next = list.nextDueDate();
    return Column(children: [
      Text('${list.words.length} palavras salvas · ${list.masteredCount()} dominadas', style: const TextStyle(color: Colors.white60)),
      if (next != null) Text('Próxima revisão ${relativeTime(next)}', style: const TextStyle(color: Colors.white60)),
    ]);
  }

  Widget _finished() {
    final due = app.savedWords.list.due().length;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.verified, size: 56, color: Colors.green),
      const SizedBox(height: 12),
      const Text('Revisão concluída!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Você revisou $_reviewed cartões e lembrou de $_remembered '
          '(${_reviewed == 0 ? 0 : _remembered * 100 ~/ _reviewed}%).'),
      const SizedBox(height: 8),
      _stats(),
      const SizedBox(height: 16),
      if (due > 0) FilledButton(onPressed: () => _start(all: false), child: Text('Continuar revisando ($due)')),
    ]);
  }

  Widget _empty() {
    if (app.savedWords.list.words.isEmpty) {
      return const Center(
        child: Text('Nenhuma palavra salva ainda.\nClique numa palavra da legenda e toque em 🔖 para salvar.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
      );
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.check_circle, size: 56, color: Colors.green),
      const SizedBox(height: 12),
      const Text('Tudo em dia!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _stats(),
      const SizedBox(height: 16),
      OutlinedButton(onPressed: () => _start(all: true), child: const Text('Revisar todas mesmo assim')),
    ]);
  }
}
