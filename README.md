# English with Movies & Music

Aplicativo de macOS para aprender inglês com filmes e músicas.

- **Arraste um filme ou uma música** para a janela. O app transcreve todas as falas no seu Mac, sem internet e sem custo.
- **A legenda aparece abaixo do vídeo**: a fala atual fica em **negrito** e a palavra que está sendo dita é destacada em tempo real.
- **Clique em qualquer palavra** para ver o significado no dicionário, a pronúncia e até **3 exemplos de frases**. Quando o dicionário tem menos de 3 exemplos, o app completa com falas do próprio filme ou da própria música.
- Clique no horário de uma fala para pular até ela.
- **Baixe vídeos do YouTube** colando o link. Eles são salvos em `~/Movies/English with Movies`.
- Já tem a legenda? Importe um `.srt` e a transcrição é pulada.

## Como funciona

```
link do YouTube ──yt-dlp──┐
arquivo (mp4, mov, mkv, mp3, m4a...)
   │  ffmpeg: extrai o áudio (16 kHz mono); converte .mkv e vídeos VP9/AV1 para H.264
   ▼
whisper.cpp: transcrição local com o tempo de cada palavra
   ▼
LinguaCore: monta as falas, sincroniza com o player e consulta o dicionário
   ▼
SwiftUI: player em cima e legenda interativa embaixo
```

| Parte | Tecnologia (tudo grátis) |
|---|---|
| Interface | SwiftUI + AVKit (macOS 14+) |
| Download | [yt-dlp](https://github.com/yt-dlp/yt-dlp) (prefere H.264 até 1080p) |
| Transcrição | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) com aceleração Metal |
| Dicionário | Dicionário do macOS (offline) e [Free Dictionary API](https://dictionaryapi.dev) como reserva |
| Pronúncia | `AVSpeechSynthesizer` (vozes do sistema) |
| Cache | Cada arquivo é transcrito uma vez, em `~/Library/Application Support/EnglishWithMovies` |
| Cópias convertidas | Vídeos .mkv, VP9 ou AV1 viram cópias em H.264 na pasta `work`. O botão **Limpar cópias** (🗑) apaga essas cópias, menos a que está tocando. |

## Requisitos

```sh
brew install ffmpeg whisper-cpp yt-dlp
```

O YouTube muda com frequência. Se um download falhar com "HTTP Error 403", atualize com `brew upgrade yt-dlp`.

Na primeira transcrição, o app baixa o modelo escolhido na barra de ferramentas:

| Modelo | Tamanho | Uso |
|---|---|---|
| base | 148 MB | rápido, bom para diálogos claros |
| small | 488 MB | equilíbrio entre velocidade e precisão |
| medium (q5) | 539 MB | mais preciso; melhor para músicas |

## Rodando

```sh
swift run EnglishWithMovies               # abre o app
swift run EnglishWithMovies filme.mp4     # abre já com um arquivo
swift run EnglishWithMovies "https://www.youtube.com/watch?v=..."   # baixa e abre
./scripts/build-app.sh                    # gera build/English with Movies.app
swift run LinguaCoreChecks                # verificações da lógica principal
```

Não precisa do Xcode: as Command Line Tools bastam.

## Estrutura

```
Sources/
  LinguaCore/          lógica sem interface (reutilizável no iPhone/iPad)
    Transcript.swift         modelo de falas e palavras com tempo
    WhisperJSONParser.swift  lê a saída do whisper.cpp
    SRTParser.swift          importa legendas .srt
    Dictionary.swift         dicionário, normalização de palavras
  EnglishWithMovies/   app macOS (SwiftUI)
  LinguaCoreChecks/    verificações automáticas
scripts/build-app.sh   empacota o .app
```

## Próximos passos

- **iPhone/iPad**: o `LinguaCore` já compila para iOS. Basta criar as telas e trocar o whisper-cli pelo [WhisperKit](https://github.com/argmaxinc/WhisperKit).
- **Windows/Android**: SwiftUI não roda nessas plataformas. A interface precisaria ser refeita (por exemplo, em Flutter), reaproveitando a mesma arquitetura e o formato dos dados.
- Separar a voz da música com o [Demucs](https://github.com/facebookresearch/demucs) para melhorar a transcrição de músicas.
- Lista de palavras salvas para revisão.
