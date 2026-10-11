import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/review.dart';
import '../core/saved_words.dart';
import '../core/word_normalizer.dart';
import '../services/app_controller.dart';
import 'common.dart';
import 'theme.dart';

enum ReviewMode {
  englishToPortuguese('Inglês → Português', 'EN → PT'),
  portugueseToEnglish('Português → Inglês', 'PT → EN'),
  listening('Ouvir', 'Ouvir');

  const ReviewMode(this.title, this.shortTitle);
  final String title;

  /// For phone screens.
  final String shortTitle;
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: EdgeInsets.fromLTRB(isCompact(context) ? 16 : 28, 12, isCompact(context) ? 16 : 28, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Short windows (a phone on its side) keep the room for the card.
                  if (MediaQuery.sizeOf(context).height >= 600) ...[
                    ScreenTitle('Revisão',
                        subtitle: isCompact(context) ? null : 'Cartões com repetição espaçada: quem você erra volta logo, quem você sabe volta depois.'),
                    const SizedBox(height: 16),
                  ],
                  _ModePicker(
                    mode: _mode,
                    onChanged: (mode) {
                      setState(() {
                        _mode = mode;
                        _flipped = false;
                      });
                      _speakIfListening();
                    },
                  ),
                  const SizedBox(height: 18),
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
    );
  }

  Widget _progress() {
    final done = _sessionSize - _queue.toSet().length;
    return Row(children: [
      Expanded(child: GradientProgress(value: _sessionSize == 0 ? 0 : done / _sessionSize)),
      const SizedBox(width: 12),
      Text('$done/$_sessionSize', style: const TextStyle(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
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
                  gradient: LinearGradient(
                    colors: [AppColors.indigo.withValues(alpha: 0.28), AppColors.violet.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.03)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.violet.withValues(alpha: 0.45)),
                  boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
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
      GlassIconButton(icon: Icons.volume_up_rounded, tooltip: 'Ouvir a pronúncia', onPressed: () => app.speaker.say(word.word));

  Widget _front(SavedWord word) {
    switch (_mode) {
      case ReviewMode.englishToPortuguese:
        return Column(children: [
          GradientText(word.word, textAlign: TextAlign.center, style: const TextStyle(fontSize: 50, fontWeight: FontWeight.w900)),
          if (word.phonetic != null) Text(word.phonetic!, style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 10),
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
          GlassIconButton(icon: Icons.volume_up_rounded, tooltip: 'Ouvir de novo', size: 96, color: AppColors.violet, onPressed: () => app.speaker.say(word.word)),
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
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GlassButton(
              label: 'Ver no ${word.sourceName ?? 'filme'}',
              icon: Icons.movie_rounded,
              onPressed: () => app.open(source, at: word.sourceTime ?? 0),
            ),
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
      return PrimaryButton(
        expand: true,
        icon: Icons.flip_rounded,
        // The keyboard shortcuts only exist on a computer.
        label: isMobile ? 'Mostrar resposta' : 'Mostrar resposta  (espaço)',
        onPressed: () => setState(() => _flipped = true),
      );
    }
    const colors = [AppColors.red, AppColors.yellow, AppColors.green, AppColors.blue];
    return Row(children: [
      for (final grade in ReviewGrade.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: colors[grade.index].withValues(alpha: 0.22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors[grade.index].withValues(alpha: 0.6)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _answer(grade),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Column(children: [
                    Text(isMobile ? grade.title : '${grade.title}  (${grade.index + 1})',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(describeNextReview(word.review, grade, DateTime.now()), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _stats() {
    final list = app.savedWords.list;
    final next = list.nextDueDate();
    return Column(children: [
      Text('${list.words.length} palavras salvas · ${list.masteredCount()} dominadas', style: const TextStyle(color: AppColors.textDim)),
      if (next != null) Text('Próxima revisão ${relativeTime(next)}', style: const TextStyle(color: AppColors.textDim)),
    ]);
  }

  Widget _finished() {
    final due = app.savedWords.list.due().length;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const EmptyStateIcon(Icons.verified_rounded),
      const SizedBox(height: 12),
      const Text('Revisão concluída!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('Você revisou $_reviewed cartões e lembrou de $_remembered '
          '(${_reviewed == 0 ? 0 : _remembered * 100 ~/ _reviewed}%).'),
      const SizedBox(height: 8),
      _stats(),
      const SizedBox(height: 16),
      if (due > 0) PrimaryButton(label: 'Continuar revisando ($due)', onPressed: () => _start(all: false)),
    ]);
  }

  Widget _empty() {
    if (app.savedWords.list.words.isEmpty) {
      return const EmptyState(
          icon: Icons.style_rounded,
          title: 'Nenhuma palavra salva ainda',
          text: 'Toque numa palavra da legenda e depois em 🔖 para salvar. Ela aparece aqui para revisar.');
    }
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const EmptyStateIcon(Icons.check_circle_rounded),
      const SizedBox(height: 12),
      const Text('Tudo em dia!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      _stats(),
      const SizedBox(height: 16),
      OutlinedButton(onPressed: () => _start(all: true), child: const Text('Revisar todas mesmo assim')),
    ]);
  }
}

/// The review modes as a glass capsule; the selected one is filled with the brand gradient.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});
  final ReviewMode mode;
  final ValueChanged<ReviewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.stroke)),
      child: Row(children: [
        for (final option in ReviewMode.values)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: option == mode ? AppColors.brand : null,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(compact ? option.shortTitle : option.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: option == mode ? Colors.white : AppColors.textDim)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
