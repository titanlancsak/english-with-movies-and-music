"""Phoneme recognizer worker.

Reads one WAV path per line on stdin (16 kHz mono, 16-bit) and writes one JSON line per request:
{"phonemes": ["h", "ə", ...]} or {"error": "..."}.
Kept running by the app so the model is loaded only once.

Usage: python worker.py <folder with model.onnx and vocab.json>
On Windows it ships as a standalone program built with PyInstaller (see .github/workflows/windows.yml).
"""
import json
import os
import sys
import wave

import numpy as np
import onnxruntime as ort


def load_wav(path: str) -> np.ndarray:
    with wave.open(path, "rb") as wav:
        if wav.getsampwidth() != 2 or wav.getframerate() != 16000:
            raise ValueError("expected 16 kHz 16-bit WAV")
        audio = np.frombuffer(wav.readframes(wav.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if wav.getnchannels() > 1:
            audio = audio.reshape(-1, wav.getnchannels()).mean(axis=1)
    # Same normalization as Wav2Vec2FeatureExtractor (do_normalize=True).
    return (audio - audio.mean()) / np.sqrt(audio.var() + 1e-7)


def main(folder: str) -> None:
    # Windows pipes default to the ANSI code page; the protocol is UTF-8 (IPA symbols, accented paths).
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(os.path.join(folder, "model.onnx"), options, providers=["CPUExecutionProvider"])
    with open(os.path.join(folder, "vocab.json"), encoding="utf-8") as f:
        vocab = json.load(f)
    symbols = {index: symbol for symbol, index in vocab.items()}
    special = {vocab.get(token) for token in ("<pad>", "<s>", "</s>", "<unk>")}
    blank = vocab.get("<pad>", 0)

    print(json.dumps({"ready": True}), flush=True)
    for line in sys.stdin:
        path = line.strip()
        if not path:
            continue
        try:
            audio = load_wav(path)
            logits = session.run(["logits"], {"input_values": audio[np.newaxis, :]})[0][0]
            ids = logits.argmax(axis=-1)
            # Greedy CTC decoding: merge repeats, drop blanks.
            phonemes = []
            previous = blank
            for index in ids:
                index = int(index)
                if index != previous and index != blank and index not in special:
                    phonemes.append(symbols[index])
                previous = index
            print(json.dumps({"phonemes": phonemes}, ensure_ascii=False), flush=True)
        except Exception as error:  # report and keep serving
            print(json.dumps({"error": str(error)}), flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
