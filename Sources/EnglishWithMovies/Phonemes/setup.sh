#!/bin/zsh
# Installs the phoneme recognizer used by the pronunciation "sounds" analysis.
#
# Model: facebook/wav2vec2-lv-60-espeak-cv-ft (Apache 2.0), converted to ONNX and
# quantized to int8 so it runs with ONNX Runtime only (no PyTorch at runtime).
#
# Usage: setup.sh <target folder>
# Prints "PROGRESS <0-100> <message>" lines for the app.
set -euo pipefail

TARGET="${1:?target folder}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$TARGET/build-tmp"
mkdir -p "$TARGET"
rm -rf "$BUILD"
trap 'rm -rf "$BUILD"' EXIT

progress() { echo "PROGRESS $1 $2"; }

# Python 3.12 via uv when available (fast, isolated); otherwise the system python3.
# --clear: a retry after a failed install starts from a clean environment.
make_venv() {
    if command -v uv >/dev/null 2>&1; then
        uv venv --quiet --clear --python 3.12 "$1"
    else
        python3 -m venv --clear "$1"
    fi
}
install() {
    local venv="$1"; shift
    if command -v uv >/dev/null 2>&1; then
        VIRTUAL_ENV="$venv" uv pip install --quiet "$@"
    else
        "$venv/bin/pip" install --quiet --disable-pip-version-check "$@"
    fi
}

command -v espeak-ng >/dev/null 2>&1 || { echo "ERROR espeak-ng não encontrado. Instale com: brew install espeak-ng"; exit 1; }

progress 5 "Preparando o Python…"
make_venv "$TARGET/venv"
install "$TARGET/venv" "onnxruntime>=1.20" "numpy>=1.26"

progress 15 "Instalando ferramentas de conversão (temporárias)…"
make_venv "$BUILD/venv"
install "$BUILD/venv" torch "transformers>=4.40,<5" "onnx>=1.16" "onnxruntime>=1.20" "numpy>=1.26"

progress 35 "Baixando e convertendo o modelo de fonemas (1,3 GB, só desta vez)…"
HF_HOME="$BUILD/hf" "$BUILD/venv/bin/python" "$HERE/convert.py" "$TARGET"

progress 95 "Limpando arquivos temporários…"
rm -rf "$BUILD"
cp "$HERE/worker.py" "$TARGET/worker.py"
progress 100 "Pronto"
