# tools/build_index.py — construye índices FAISS por idioma
from pathlib import Path
import json, re
import faiss
from sentence_transformers import SentenceTransformer
import numpy as np

BASE = Path(__file__).resolve().parents[1]
DS   = BASE / "data" / "ds"
CORPORA = {
    "es-419": BASE / "data" / "corpus_txt_es_419",
    "es-MX":  BASE / "data" / "corpus_txt_es_mx",
    "en-US":  BASE / "data" / "corpus_txt_en_us",
}
EMB_MODEL = "distiluse-base-multilingual-cased-v2"

def chunk_text(t: str, max_chars=800):
    t = re.sub(r"\s+", " ", t)
    out = []
    for i in range(0, len(t), max_chars):
        out.append(t[i:i+max_chars])
    return out

def build_for(lang: str, folder: Path):
    if not folder.exists(): return
    DS.mkdir(parents=True, exist_ok=True)
    meta = []; chunks = []
    for p in folder.glob("*.txt"):
        txt = p.read_text(encoding="utf-8", errors="ignore")
        for i, ch in enumerate(chunk_text(txt)):
            meta.append({"source": p.name, "chunk_id": i})
            chunks.append(ch)
    if not chunks:
        return
    model = SentenceTransformer(EMB_MODEL)
    X = model.encode(chunks, convert_to_numpy=True, normalize_embeddings=True)
    dim = X.shape[1]
    index = faiss.IndexFlatIP(dim)
    index.add(X.astype(np.float32))
    # guardar
    if lang == "es-MX":
        faiss.write_index(index, str(DS / "faiss_es_mx.index"))
        (DS / "meta_es_mx.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    elif lang == "en-US":
        faiss.write_index(index, str(DS / "faiss_en_us.index"))
        (DS / "meta_en_us.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    else:
        faiss.write_index(index, str(DS / "faiss_es_419.index"))
        (DS / "meta_es_419.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")

if __name__ == "__main__":
    for lg, folder in CORPORA.items():
        build_for(lg, folder)
    print("Índices FAISS construidos.")
