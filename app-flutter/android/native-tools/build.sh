#!/usr/bin/env bash
# Builds the command-line tools the Android app runs, for 64-bit ARM phones:
#   - whisper-cli (whisper.cpp), the speech recognizer;
#   - ffmpeg and ffprobe, a small build that reads audio and makes library covers.
#
# Android only lets an app run programs that ship inside its APK as native libraries,
# so they are saved as app/src/main/jniLibs/arm64-v8a/lib<name>.so and run from the
# app's native library folder (see MainActivity.kt and lib/services/paths.dart).
#
# Usage: build.sh            (needs ANDROID_NDK_HOME or the NDK in ~/Library/Android/sdk/ndk)
# Runs on macOS and Linux (the GitHub workflow).
set -euo pipefail

WHISPER_VERSION="${WHISPER_VERSION:-b5454}"
FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
API=24

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../app/src/main/jniLibs/arm64-v8a"
WORK="${WORK:-$HERE/.build}"
mkdir -p "$OUT" "$WORK"

NDK="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* 2>/dev/null | sort -V | tail -1)}"
[ -d "$NDK" ] || { echo "Android NDK not found (set ANDROID_NDK_HOME)"; exit 1; }
HOST="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
echo "NDK: $NDK"

# --- whisper.cpp -------------------------------------------------------------
# Two builds: one for any 64-bit ARM phone, and a faster one for phones with the
# dot-product and half-precision instructions (most phones since 2018); the app
# picks the fast one when /proc/cpuinfo lists "asimddp" and "fphp".
build_whisper() {  # <output name> <ARM architecture>
    local name="$1" arch="$2" build="$WORK/whisper-build-$1"
    [ -f "$OUT/lib$name.so" ] && return
    [ -d "$WORK/whisper.cpp" ] || git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp "$WORK/whisper.cpp"
    # One self-contained program: static libraries, static C++ runtime, no OpenMP.
    cmake -S "$WORK/whisper.cpp" -B "$build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_static \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH="$arch" \
        -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_SDL2=OFF -DWHISPER_CURL=OFF > "$build.cmake.log"
    cmake --build "$build" --target whisper-cli -j "$JOBS" > "$build.log"
    cp "$build/bin/whisper-cli" "$OUT/lib$name.so"
    "$TOOLCHAIN/bin/llvm-strip" "$OUT/lib$name.so"
    echo "$name: $(du -h "$OUT/lib$name.so" | cut -f1)"
}
build_whisper whisper_cli armv8-a
build_whisper whisper_cli_fast armv8.2-a+dotprod+fp16

# --- FFmpeg ------------------------------------------------------------------
if [ ! -f "$OUT/libffmpeg.so" ] || [ ! -f "$OUT/libffprobe.so" ]; then
    if [ ! -d "$WORK/ffmpeg-$FFMPEG_VERSION" ]; then
        curl -sSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" | tar -xJ -C "$WORK"
    fi
    cd "$WORK/ffmpeg-$FFMPEG_VERSION"
    # Only what the app needs: decode the audio of common films and songs to 16 kHz WAV,
    # and grab one video frame as a JPEG cover. LGPL build (no GPL parts enabled).
    ./configure \
        --prefix="$WORK/ffmpeg-out" \
        --enable-cross-compile --target-os=android --arch=aarch64 --cpu=armv8-a \
        --cc="$TOOLCHAIN/bin/aarch64-linux-android$API-clang" \
        --cxx="$TOOLCHAIN/bin/aarch64-linux-android$API-clang++" \
        --nm="$TOOLCHAIN/bin/llvm-nm" --ar="$TOOLCHAIN/bin/llvm-ar" \
        --ranlib="$TOOLCHAIN/bin/llvm-ranlib" --strip="$TOOLCHAIN/bin/llvm-strip" \
        --enable-pic --enable-small --disable-debug --disable-doc --disable-network \
        --disable-autodetect --disable-everything --disable-ffplay \
        --enable-ffmpeg --enable-ffprobe \
        --enable-protocol=file,pipe \
        --enable-demuxer=mov,matroska,webm_dash_manifest,avi,mp3,aac,ogg,wav,flac,mpegts,flv,asf,m4v \
        --enable-decoder=aac,aac_latm,mp3,mp3float,mp2,opus,vorbis,flac,alac,ac3,eac3,wmav2,pcm_s16le,pcm_s24le,pcm_f32le \
        --enable-decoder=h264,hevc,vp8,vp9,mpeg4,mjpeg,png \
        --enable-parser=aac,mpegaudio,opus,vorbis,flac,ac3,h264,hevc,vp8,vp9,mpeg4video \
        --enable-encoder=pcm_s16le,mjpeg \
        --enable-muxer=wav,image2,mjpeg \
        --enable-filter=aresample,aformat,anull,scale,format,null,copy \
        --enable-swresample --enable-swscale > "$WORK/ffmpeg-configure.log"
    make -j "$JOBS" > "$WORK/ffmpeg-build.log" 2>&1
    cp ffmpeg "$OUT/libffmpeg.so"
    cp ffprobe "$OUT/libffprobe.so"
    "$TOOLCHAIN/bin/llvm-strip" "$OUT/libffmpeg.so" "$OUT/libffprobe.so"
    echo "ffmpeg: $(du -h "$OUT/libffmpeg.so" | cut -f1), ffprobe: $(du -h "$OUT/libffprobe.so" | cut -f1)"
fi

ls -la "$OUT"
