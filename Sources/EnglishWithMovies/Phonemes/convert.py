"""Converts facebook/wav2vec2-lv-60-espeak-cv-ft to an int8 ONNX model.

Usage: python convert.py <target folder>
Writes <target>/model.onnx and <target>/vocab.json.
"""
import json
import os
import sys

import torch
from huggingface_hub import hf_hub_download
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import Wav2Vec2ForCTC

MODEL = "facebook/wav2vec2-lv-60-espeak-cv-ft"


def main(target: str) -> None:
    model = Wav2Vec2ForCTC.from_pretrained(MODEL)
    model.eval()
    # Only the vocabulary is needed (loading the tokenizer would require the phonemizer library).
    with open(hf_hub_download(MODEL, "vocab.json"), encoding="utf-8") as f:
        vocab = json.load(f)
    print("PROGRESS 60 Convertendo para ONNX…", flush=True)

    full = os.path.join(target, "model-fp32.onnx")
    dummy = torch.zeros(1, 16000)
    torch.onnx.export(
        model,
        (dummy,),
        full,
        input_names=["input_values"],
        output_names=["logits"],
        dynamic_axes={"input_values": {1: "samples"}, "logits": {1: "frames"}},
        opset_version=17,
        dynamo=False,
    )

    print("PROGRESS 80 Compactando o modelo…", flush=True)
    quantize_dynamic(full, os.path.join(target, "model.onnx"), weight_type=QuantType.QInt8)
    os.remove(full)
    data = full + ".data"
    if os.path.exists(data):
        os.remove(data)

    with open(os.path.join(target, "vocab.json"), "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1])
