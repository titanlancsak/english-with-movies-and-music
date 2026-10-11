<img src="Resources/AppIcon.png" width="128" alt="Ícone do app">

# English with Movies & Music

Aplicativo de macOS para aprender inglês com filmes e músicas.

- **Biblioteca estilo Netflix** ao abrir o app: destaque com o último conteúdo, fileiras de capas (Continuar assistindo, Baixados do YouTube, Filmes e vídeos, Músicas) e o vídeo continua de onde você parou.
- **Arraste um filme ou uma música** para a janela. O app transcreve todas as falas no seu Mac, sem internet e sem custo.
- **A legenda aparece abaixo do vídeo**: a fala atual fica em **negrito** e a palavra que está sendo dita é destacada em tempo real.
- **Clique em qualquer palavra** para ver o significado no dicionário, a pronúncia e até **3 exemplos de frases**. Quando o dicionário tem menos de 3 exemplos, o app completa com falas do próprio filme ou da própria música.
- **Tradução para português**: o botão "Tradução" mostra a tradução embaixo de cada fala, e o popup da palavra traduz a palavra e a frase. Tudo roda no próprio Mac, sem internet depois do primeiro download do idioma.
- **Pratique a pronúncia**: clique no 🎤 ao lado de uma fala (ou ⌘R na fala atual), ouça o personagem e repita no microfone. O app dá uma **nota de 0 a 100** (precisão, fluência e completude), marca cada palavra como correta, pouco clara, errada ou faltando, e dá dicas. O **histórico de notas** fica salvo por fala (⇧⌘H).
- **Análise por som** (opcional): mostra exatamente qual som saiu errado (o “th” falado como /t/, o R americano, “ship” × “sheep”, um “i” a mais no final da palavra…), com dicas de como posicionar a língua e os lábios.
- **Salve palavras** (🔖 no popup) para revisar depois. A lista guarda o significado, a frase em que a palavra apareceu e o filme. Ela também volta direto para o trecho e exporta **CSV** (com a tradução) para o Anki (⇧⌘S abre a lista).
- Descrições de som como `[Music]`, `(background music playing)` e `♪` são removidas da legenda.
- **Revise as palavras salvas** com cartões (⇧⌘R) e repetição espaçada, como no Anki: quem você acerta volta em 1, 3, 8 dias…; quem você erra volta em 10 minutos. Três modos: Inglês → Português, Português → Inglês e Ouvir.
- Clique no horário de uma fala para pular até ela.
- **Baixe vídeos do YouTube** colando o link. Eles ficam na biblioteca (pasta `~/Movies/English with Movies`); passe o mouse na capa e clique na 🗑 para apagar o vídeo, a cópia convertida e a transcrição.
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
| Tradução | Framework Translation da Apple (macOS 15+, offline) |
| Análise por som | [wav2vec2 de fonemas da Meta](https://huggingface.co/facebook/wav2vec2-lv-60-espeak-cv-ft) (Apache 2.0) convertido para ONNX int8 + [espeak-ng](https://github.com/espeak-ng/espeak-ng) para os sons esperados |
| Pronúncia | `AVSpeechSynthesizer` (vozes do sistema) |
| Cache | Cada arquivo é transcrito uma vez, em `~/Library/Application Support/EnglishWithMovies` |
| Cópias convertidas | Vídeos .mkv, VP9 ou AV1 viram cópias em H.264 na pasta `work`. O botão **Limpar cópias** (🗑) apaga essas cópias, menos a que está tocando. |

## Requisitos

```sh
brew install ffmpeg whisper-cpp yt-dlp
```

Para a análise por som, também `brew install espeak-ng` (e `uv` ou Python 3). Ela é instalada pelo próprio app na janela de prática: baixa cerca de 1,5 GB uma vez, converte o modelo e depois ocupa ~400 MB em `~/Library/Application Support/EnglishWithMovies/phonemes`.

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
    SoundAnnotations.swift   remove descrições de som ([Music], ♪...)
    Dictionary.swift         dicionário, normalização de palavras
    SavedWords.swift         lista de palavras salvas e exportação CSV
    Review.swift             revisão com repetição espaçada (SM-2)
    Pronunciation.swift      nota de pronúncia e histórico de prática
    Phonemes.swift           comparação som a som e dicas
  EnglishWithMovies/   app macOS (SwiftUI)
    Phonemes/                instalação e execução do modelo de fonemas (Python/ONNX)
  LinguaCoreChecks/    verificações automáticas
Resources/AppIcon.*    ícone do app (gerado por scripts/make-icon.swift)
scripts/build-app.sh   empacota o .app
scripts/make-icon.swift  desenha o ícone: swift scripts/make-icon.swift
```

## Próximos passos

- **iPhone/iPad**: o `LinguaCore` já compila para iOS. Basta criar as telas e trocar o whisper-cli pelo [WhisperKit](https://github.com/argmaxinc/WhisperKit).
- **Windows/Android**: SwiftUI não roda nessas plataformas. A interface precisaria ser refeita (por exemplo, em Flutter), reaproveitando a mesma arquitetura e o formato dos dados.
- Separar a voz da música com o [Demucs](https://github.com/facebookresearch/demucs) para melhorar a transcrição de músicas.
