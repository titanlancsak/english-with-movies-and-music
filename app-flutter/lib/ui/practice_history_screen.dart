import 'package:flutter/material.dart';

import '../core/pronunciation.dart';
import '../services/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// Every practiced sentence and its scores.
class PracticeHistoryScreen extends StatelessWidget {
  const PracticeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.practice,
      builder: (context, _) {
        final history = app.practice.history;
        final average = history.averageScore;
        final compact = isCompact(context);
        final margin = compact ? 16.0 : 28.0;
        final cards = [
          _Summary('Frases praticadas', '${history.records.length}', Icons.chat_bubble_rounded, AppColors.indigo),
          _Summary('Tentativas', '${history.attemptCount}', Icons.mic_rounded, AppColors.violet),
          _Summary('Média atual', average?.toString() ?? '–', Icons.trending_up_rounded, average == null ? AppColors.orange : scoreColor(average)),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(margin, 12, margin, 24),
          children: [
            ScreenTitle('Pronúncia',
                subtitle: isMobile ? 'Toque no 🎤 ao lado de uma fala para praticar.' : 'Clique no 🎤 ao lado de uma fala para praticar.'),
            const SizedBox(height: 18),
            compact
                ? Column(children: [for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: card)])
                : Row(children: [
                    for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: cards[i])],
                  ]),
            const SizedBox(height: 18),
            if (history.records.isEmpty)
              const SizedBox(
                height: 260,
                child: EmptyState(
                    icon: Icons.mic_none_rounded,
                    title: 'Nenhuma fala praticada ainda',
                    text: 'Abra um filme, escolha uma fala e repita no microfone para receber uma nota.'),
              )
            else
              for (final record in history.recent)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: _RecordRow(record: record)),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.title, this.value, this.icon, this.color);
  final String title, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          IconTile(icon, color: color, size: 42, glow: true),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            Text(title, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ]),
        ]),
      );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});
  final PracticeRecord record;

  @override
  Widget build(BuildContext context) {
    final scores = record.attempts.reversed.take(10).toList().reversed.map((a) => a.score).toList();
    return GestureDetector(
      onLongPress: () => app.practice.remove(record.id),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          ScoreRing(score: record.last?.score ?? 0, size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(record.sentence, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                [
                  if (record.source != null) '${record.source} · ${formatTime(record.lineStart)}',
                  if (record.last != null) relativeTime(record.last!.date),
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TagChip('melhor ${record.best}', icon: Icons.emoji_events_rounded, color: scoreColor(record.best)),
            const SizedBox(height: 6),
            // Tiny bars with the latest scores, oldest on the left.
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final score in scores)
                Container(
                  width: 5,
                  height: (score / 100 * 22).clamp(2, 22),
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(color: scoreColor(score), borderRadius: BorderRadius.circular(2)),
                ),
            ]),
            const SizedBox(height: 4),
            Text('${record.attempts.length} tentativa${record.attempts.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}
