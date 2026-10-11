import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../services/app_controller.dart';
import '../services/gpu.dart';
import '../services/media_tools.dart';
import 'common.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context) => showDialog(context: context, builder: (_) => const SettingsDialog());

/// Transcription, study goal, sync between devices, graphics card and updates.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: isCompact(context) ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 820),
        child: ListenableBuilder(
          listenable: Listenable.merge([app, app.study, app.sync, app.gpu, app.updates]),
          builder: (context, _) => Stack(children: [
            const Positioned.fill(child: AuroraBackground()),
            ListView(shrinkWrap: true, padding: const EdgeInsets.all(22), children: [
              const GradientText('Ajustes', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _section('Transcrição', Icons.graphic_eq_rounded, [
                _dropdown<WhisperModel>(
                  'Modelo',
                  app.model,
                  {for (final m in WhisperModel.values) m: m.title},
                  app.setModel,
                ),
                const Text(
                    'Os modelos maiores são mais precisos e mais lentos. Vídeos com legenda (do YouTube ou um .srt na mesma pasta) usam a legenda e não precisam ser transcritos.',
                    style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                if (GpuWhisper.hasNvidia) ...[const SizedBox(height: 8), _gpu()],
              ]),
              _section('Estudo', Icons.local_fire_department_rounded, [
                _dropdown<int>('Meta diária', app.study.goalMinutes, {for (final m in const [5, 10, 15, 20, 30, 45, 60]) m: '$m minutos'},
                    (value) => app.study.goalMinutes = value),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sublinhar as palavras difíceis (fora das 5.000 mais comuns)'),
                  value: app.highlightUncommon,
                  onChanged: app.setHighlightUncommon,
                ),
              ]),
              _section('Sincronizar com outros aparelhos', Icons.sync_rounded, isMobile ? _phoneSync(context) : _folderSync()),
              _section('Atualizações', Icons.system_update_alt_rounded, [
                Row(children: [
                  const Text('Versão $appVersion', style: TextStyle(color: AppColors.textDim)),
                  const Spacer(),
                  if (app.updates.available != null)
                    PrimaryButton(label: 'Baixar a versão ${app.updates.availableVersion}', onPressed: app.updates.download)
                  else
                    GlassButton(label: 'Procurar atualização', onPressed: () => app.updates.check(ignoreDismissed: true)),
                ]),
              ]),
              Align(alignment: Alignment.centerRight, child: PrimaryButton(label: 'Pronto', onPressed: () => Navigator.pop(context))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.violet),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _dropdown<T>(String label, T value, Map<T, String> options, ValueChanged<T> onChanged) => Row(children: [
        Text(label),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]);

  /// Windows with an NVIDIA card: optional faster transcription.
  Widget _gpu() {
    final gpu = app.gpu;
    final progress = gpu.progress;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Placa de vídeo NVIDIA encontrada', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      if (progress != null) ...[
        GradientProgress(value: progress),
        const SizedBox(height: 4),
        Text('Baixando… ${(progress * 100).round()}%', style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
      ] else if (gpu.installed) ...[
        Text(gpu.failed ? 'A transcrição pela placa de vídeo falhou neste computador; o app usa o processador.' : 'A transcrição usa a placa de vídeo (bem mais rápida).',
            style: TextStyle(fontSize: 12, color: gpu.failed ? AppColors.orange : AppColors.green)),
        const SizedBox(height: 6),
        GlassButton(label: 'Remover', onPressed: gpu.remove),
      ] else ...[
        const Text('Transcreva várias vezes mais rápido usando a placa de vídeo. Download único de cerca de 270 MB.',
            style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        if (gpu.error != null) Text(gpu.error!, style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        const SizedBox(height: 6),
        PrimaryButton(label: 'Usar a placa de vídeo', icon: Icons.bolt_rounded, onPressed: gpu.install),
      ],
    ]);
  }

  List<Widget> _folderSync() {
    final sync = app.sync;
    return [
      const Text(
          'Escolha uma pasta que já sincroniza sozinha (Google Drive, Dropbox, OneDrive ou iCloud Drive). As palavras salvas, o histórico de pronúncia e o tempo de estudo ficam iguais em todos os aparelhos que usarem a mesma pasta, inclusive no Mac.',
          style: TextStyle(fontSize: 12, color: AppColors.textDim)),
      const SizedBox(height: 8),
      Row(children: [
        Icon(sync.folder == null ? Icons.cloud_off_rounded : Icons.folder_rounded, size: 18, color: sync.folder == null ? AppColors.textDim : AppColors.violet),
        const SizedBox(width: 8),
        Expanded(child: Text(sync.folder ?? 'Desligada', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      if (sync.status.isNotEmpty)
        Text(sync.status, style: TextStyle(fontSize: 12, color: sync.status.startsWith('Não') ? AppColors.orange : AppColors.textDim)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PrimaryButton(
          label: sync.folder == null ? 'Escolher pasta…' : 'Trocar pasta…',
          onPressed: () async {
            final folder = await FilePicker.getDirectoryPath(dialogTitle: 'Escolha uma pasta sincronizada');
            if (folder != null) sync.setFolder(folder);
          },
        ),
        if (sync.folder != null) ...[
          GlassButton(label: 'Sincronizar agora', onPressed: sync.syncNow),
          GlassButton(label: 'Desligar', onPressed: () => sync.setFolder(null)),
        ],
      ]),
    ];
  }

  /// A phone cannot write into Google Drive's folder, so the file is opened and saved by hand.
  List<Widget> _phoneSync(BuildContext context) {
    final sync = app.sync;
    return [
      const Text(
          'Para juntar os dados com o computador: lá, ligue a sincronização com uma pasta do Google Drive. Aqui, toque em "Abrir arquivo" e escolha o arquivo english-with-movies-sync.json dessa pasta. Depois toque em "Salvar arquivo" e salve-o de volta na mesma pasta (substituindo o antigo).',
          style: TextStyle(fontSize: 12, color: AppColors.textDim)),
      if (sync.status.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(sync.status, style: TextStyle(fontSize: 12, color: sync.status.startsWith('Este') ? AppColors.orange : AppColors.green)),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PrimaryButton(label: 'Abrir arquivo', icon: Icons.file_open_rounded, onPressed: sync.importFile),
        GlassButton(label: 'Salvar arquivo', icon: Icons.save_alt_rounded, onPressed: sync.exportFile),
      ]),
    ];
  }
}
