import 'package:flutter/material.dart';

import '../core/pronunciation.dart';
import '../services/app_controller.dart';
import 'common.dart';

/// Every practiced sentence and its scores.
class PracticeHistoryScreen extends StatelessWidget {
  const PracticeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de pronúncia')),
      body: ListenableBuilder(
        listenable: app.practice,
        builder: (context, _) {
          final history = app.practice.history;
          final average = history.averageScore;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _Summary('Frases praticadas', '${history.records.length}'),
                _Summary('Tentativas', '${history.attemptCount}'),
                _Summary('Média atual', average?.toString() ?? '–', color: average == null ? null : scoreColor(average)),
              ]),
            ),
            Expanded(
              child: history.records.isEmpty
                  ? const Center(
                      child: Text('Nenhuma fala praticada ainda.\nClique no 🎤 ao lado de uma fala para praticar.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                    )
                  : ListView(children: [for (final record in history.recent) _RecordRow(record: record)]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.title, this.value, {this.color});
  final String title, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});
  final PracticeRecord record;

  @override
  Widget build(BuildContext context) {
    final scores = record.attempts.reversed.take(10).toList().reversed.map((a) => a.score).toList();
    return ListTile(
      leading: ScoreRing(score: record.last?.score ?? 0, size: 40),
      title: Text(record.sentence, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (record.source != null) '${record.source} · ${formatTime(record.lineStart)}',
        if (record.last != null) relativeTime(record.last!.date),
      ].join('  ·  ')),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('melhor ${record.best}', style: TextStyle(color: scoreColor(record.best), fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        // Tiny bars with the latest scores, oldest on the left.
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final score in scores)
            Container(
              width: 5,
              height: (score / 100 * 22).clamp(2, 22),
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(color: scoreColor(score), borderRadius: BorderRadius.circular(1)),
            ),
        ]),
      ]),
      onLongPress: () => app.practice.remove(record.id),
    );
  }
}
