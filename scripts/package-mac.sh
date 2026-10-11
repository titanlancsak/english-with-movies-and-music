#!/bin/zsh
# Creates dist/EnglishWithMovies-macOS.zip (universal: Apple Silicon + Intel) for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh --universal
mkdir -p dist
rm -f dist/EnglishWithMovies-macOS.zip
# ditto keeps the app bundle's permissions and signature intact.
ditto -c -k --keepParent "build/English with Movies.app" dist/EnglishWithMovies-macOS.zip
echo "Pronto: dist/EnglishWithMovies-macOS.zip ($(du -h dist/EnglishWithMovies-macOS.zip | cut -f1))"
