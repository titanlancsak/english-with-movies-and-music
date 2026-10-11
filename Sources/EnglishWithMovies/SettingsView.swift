import AppKit
import SwiftUI

/// Transcription, study goal, sync between devices and updates.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var study: StudyStore
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.dismiss) private var dismiss
    @ViewState private var cleanupSize: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ajustes").font(.system(size: 26, weight: .heavy)).gradientForeground()

            section("Transcrição", icon: "waveform") {
                Picker("Modelo", selection: $model.model) {
                    ForEach(WhisperModel.allCases) { Text($0.title).tag($0) }
                }
                Text("Os modelos maiores são mais precisos e mais lentos. Vídeos com legenda (do YouTube ou um .srt na mesma pasta) usam a legenda e não precisam ser transcritos.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                Button("Liberar espaço (cópias convertidas)…") { cleanupSize = model.convertedCopiesSize() }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(model.isBusy)
            }

            section("Estudo", icon: "flame.fill") {
                Picker("Meta diária", selection: Binding(get: { study.goalMinutes }, set: { study.goalMinutes = $0 })) {
                    ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) minutos").tag($0) }
                }
                Toggle("Sublinhar as palavras difíceis (fora das 5.000 mais comuns)", isOn: $model.highlightUncommon)
            }

            section("Sincronizar com o celular e outros computadores", icon: "arrow.triangle.2.circlepath") {
                Text("Escolha uma pasta que já sincroniza sozinha (Google Drive, Dropbox, OneDrive ou iCloud Drive). As palavras salvas, o histórico de pronúncia e o tempo de estudo ficam iguais em todos os aparelhos que usarem a mesma pasta.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Image(systemName: sync.folder == nil ? "icloud.slash" : "folder.fill")
                        .foregroundStyle(sync.folder == nil ? Theme.textDim : Theme.violet)
                    Text(sync.folder?.path(percentEncoded: false) ?? "Desligada")
                        .lineLimit(1).truncationMode(.middle)
                }
                if !sync.status.isEmpty {
                    Text(sync.status).font(.caption).foregroundStyle(sync.status.hasPrefix("Não") ? Theme.orange : Theme.textDim)
                }
                HStack {
                    Button(sync.folder == nil ? "Escolher pasta…" : "Trocar pasta…", action: chooseFolder)
                        .buttonStyle(PrimaryButtonStyle())
                    if sync.folder != nil {
                        Button("Sincronizar agora") { sync.syncNow() }.buttonStyle(GlassButtonStyle())
                        Button("Desligar") { sync.setFolder(nil) }.buttonStyle(GlassButtonStyle())
                    }
                }
            }

            section("Atualizações", icon: "arrow.down.circle") {
                HStack {
                    Text("Versão \(UpdateChecker.current ?? "de desenvolvimento")").foregroundStyle(Theme.textDim)
                    Spacer()
                    if let available = updates.available {
                        Button("Baixar a versão \(available.version)") { updates.download() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Procurar atualização") {
                            UserDefaults.standard.removeObject(forKey: "dismissedUpdate")
                            Task { await updates.check() }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }

            HStack {
                Spacer()
                Button("Pronto") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(AuroraBackground())
        .environment(\.colorScheme, .dark)
        .confirmationDialog(
            (cleanupSize ?? 0) > 0
                ? "Apagar cópias convertidas (\(ByteCountFormatter.string(fromByteCount: cleanupSize ?? 0, countStyle: .file)))?"
                : "Não há cópias para apagar",
            isPresented: Binding(get: { cleanupSize != nil }, set: { if !$0 { cleanupSize = nil } })
        ) {
            if (cleanupSize ?? 0) > 0 {
                Button("Apagar", role: .destructive) { model.clearConvertedCopies() }
            } else {
                Button("OK") {}
            }
        } message: {
            Text("Os arquivos originais e as transcrições são mantidos.")
        }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Usar esta pasta"
        panel.message = "Escolha uma pasta sincronizada (Google Drive, Dropbox, OneDrive ou iCloud Drive)"
        if panel.runModal() == .OK, let url = panel.url { sync.setFolder(url) }
    }
}
