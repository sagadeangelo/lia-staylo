# app.py — LIA-Staylo Backend (0.4.2) con categorías LT y reglas MX tipadas
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, List
from pathlib import Path
import io, docx, re, os, json, difflib, subprocess, sys, uuid
import httpx
import spacy
from textstat import textstat
import yaml

# ─────────────────────────── Config ───────────────────────────
BASE_DIR = Path(__file__).parent.resolve()

# Directorio de reglas: primero variable de entorno (freeze),
# si no existe, usa BASE_DIR/rules (modo dev)
RULES_DIR = Path(os.environ.get("LIA_RULES_DIR", str(BASE_DIR / "rules")))

# LanguageTool y LLM
LT_URL   = os.environ.get("LT_URL",  "http://127.0.0.1:8081")
LLM_URLS = [
    os.environ.get("LLM_URL", "http://127.0.0.1:11434/v1/chat/completions"),
    "http://127.0.0.1:11434/api/chat",
]
MODEL_NAME = os.environ.get("LLM_MODEL", "qwen2:1.5b-instruct")

# Embeddings / RAG
EMB_MODEL        = os.environ.get("EMB_MODEL", "distiluse-base-multilingual-cased-v2")
DS_DIR           = BASE_DIR / "data" / "ds"
FAISS_INDEX_PATH = DS_DIR / "faiss.index"
FAISS_META_PATH  = DS_DIR / "meta.json"

# ─────────────────────────── App ───────────────────────────
app = FastAPI(title="LIA-Staylo Backend", version="0.4.2")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─────────────────────────── spaCy ───────────────────────────
try:
    nlp = spacy.load("es_core_news_md")
except Exception:
    nlp = None

# ───────────── Diccionario simple en memoria ─────────────
DICT = set()  # palabras permitidas/propias (case-insensitive)

# ───────────────────── Reglas ES-MX ─────────────────────
ES_MX: dict = {}

def load_es_mx():
    """Carga es_mx.yaml desde RULES_DIR (env) o BASE_DIR/rules."""
    global ES_MX
    p = RULES_DIR / "es_mx.yaml"
    if p.exists():
        try:
            ES_MX = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        except Exception:
            ES_MX = {}
    else:
        ES_MX = {}

load_es_mx()

def _match_obj(message: str, rule_id: str, start: int, end: int,
               replacements=None, category: str | None = None):
    """Objeto “match” compatible con LT + campo category opcional."""
    return {
        "message": message,
        "shortMessage": "",
        "offset": start,
        "length": max(0, end - start),
        "rule": rule_id,
        "category": category,               # TYPOS | GRAMMAR | PUNCTUATION | STYLE
        "replacements": (replacements or [])[:5],
    }

def apply_es_mx(text: str) -> list[dict]:
    """Aplica reglas locales MX/ES y etiqueta categoría adecuada."""
    out: list[dict] = []

    # Preferencias léxicas → STYLE
    for wrong, right in (ES_MX.get("prefer") or {}).items():
        rgx = re.compile(rf"\b{re.escape(wrong)}\b", flags=re.IGNORECASE)
        for m in rgx.finditer(text):
            out.append(_match_obj(
                message=f"Preferencia MX: usa «{right}» en lugar de «{m.group(0)}».",
                rule_id="ES_MX_PREFER",
                start=m.start(), end=m.end(),
                replacements=[right],
                category="STYLE",
            ))

    # Muletillas → STYLE
    for r in (ES_MX.get("muletillas") or []):
        try:
            rgx = re.compile(r.get("regex", ""), flags=re.MULTILINE)
        except re.error:
            continue
        for m in rgx.finditer(text):
            out.append(_match_obj(
                message=r.get("message", "Muletilla detectada."),
                rule_id="CUSTOM_MULE_es-419",
                start=m.start(), end=m.end(),
                category="STYLE",
            ))

    # Espaciado/puntuación → PUNCTUATION
    for r in (ES_MX.get("espacios") or []):
        try:
            rgx = re.compile(r.get("regex", ""), flags=re.MULTILINE)
        except re.error:
            continue
        for m in rgx.finditer(text):
            repl = r.get("replace")
            rep = []
            if repl is not None:
                try:
                    rep = [rgx.sub(repl, m.group(0))]
                except Exception:
                    rep = []
            out.append(_match_obj(
                message=r.get("message", "Espaciado/puntuación."),
                rule_id="ES_MX_ESPACIOS",
                start=m.start(), end=m.end(),
                replacements=rep,
                category="PUNCTUATION",
            ))

    # Diálogo → PUNCTUATION
    for _k, r in (ES_MX.get("dialogo") or {}).items():
        try:
            rgx = re.compile(r.get("regex", ""), flags=re.MULTILINE)
        except re.error:
            continue
        for m in rgx.finditer(text):
            out.append(_match_obj(
                message=r.get("message", "Convención de diálogo."),
                rule_id="ES_MX_DIALOGO",
                start=m.start(), end=m.end(),
                category="PUNCTUATION",
            ))
    return out

# ───────────────────────── Utilidades ─────────────────────────
def _normalize_spaces(s: str) -> str:
    return s.replace("\u00A0", " ")

def read_any(file_bytes: bytes, filename: str) -> str:
    name = filename.lower()
    if name.endswith((".txt", ".md")):
        txt = file_bytes.decode("utf-8", errors="ignore")
        return _normalize_spaces(txt)
    if name.endswith(".docx"):
        f = io.BytesIO(file_bytes)
        doc = docx.Document(f)
        txt = "\n".join(p.text for p in doc.paragraphs)
        return _normalize_spaces(txt)
    raise HTTPException(status_code=400, detail="Formato no soportado. Usa .txt, .md o .docx")

def spacy_stats(text: str) -> dict:
    if nlp is None:
        return {"warning": "spaCy no disponible. Ejecuta: python -m spacy download es_core_news_md"}
    text = _normalize_spaces(text)

    doc = nlp(text)
    sentences = list(doc.sents)
    words_total = sum(len(s.text.split()) for s in sentences)

    dialog_rgx = re.compile(r"(?m)^[ \t]*[—–](?=[\s\u00A0«\"'¡¿A-Za-zÁÉÍÓÚÜÑáéíóúüñ])")
    dialogs_iter = list(dialog_rgx.finditer(text))
    dialogs = len(dialogs_iter)

    dialog_examples = []
    for m in dialogs_iter[:50]:
        start = m.start()
        snippet = text[max(0, start - 30): start + 80].replace("\n", " ")
        dialog_examples.append({"offset": start, "snippet": snippet})

    long_sentences = [s.text for s in sentences if len(s.text.split()) > 30]
    pos_counts = doc.count_by(spacy.attrs.POS) if hasattr(spacy.attrs, "POS") else {}

    return {
        "sentences": len(sentences),
        "words": words_total,
        "long_sentences": len(long_sentences),
        "dialog_marks": dialogs,
        "dialog_examples": dialog_examples,
        "pos_counts": {doc.vocab[i].text: c for i, c in pos_counts.items()},
    }

async def languagetool_check(text: str, lang: str = "es") -> dict:
    """
    Llama a LanguageTool y devuelve matches con 'category'.
    - lang: 'es', 'es-419', 'es-MX', 'en-US', etc. (se mapea a 'es' o 'en-US' para LT comunitario)
    """
    text = _normalize_spaces(text)
    lt_lang = "en-US" if (lang or "").lower().startswith("en") else "es"

    url = f"{LT_URL}/v2/check"
    params = {"language": lt_lang, "enabledOnly": "false"}
    data = {"text": text}
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(url, params=params, data=data)
            r.raise_for_status()
            j = r.json()
            matches = []
            for m in j.get("matches", []):
                rule = m.get("rule", {}) or {}
                cat = (rule.get("category") or {}).get("id")  # TYPOS, GRAMMAR, PUNCTUATION, STYLE
                matches.append({
                    "message": m.get("message"),
                    "shortMessage": m.get("shortMessage"),
                    "offset": m.get("offset"),
                    "length": m.get("length"),
                    "rule": rule.get("id"),
                    "category": cat,
                    "issueType": rule.get("issueType"),
                    "replacements": [rv.get("value") for rv in m.get("replacements", [])][:5],
                })
            return {"ok": True, "matches": matches}
    except Exception as e:
        return {"ok": False, "error": str(e), "matches": []}

def filter_matches_by_dictionary(text: str, matches: List[dict]) -> List[dict]:
    if not DICT or not matches:
        return matches
    text = _normalize_spaces(text)
    allow = set(w.lower() for w in DICT)
    filtered: list[dict] = []
    for m in matches:
        try:
            off = int(m.get("offset", 0))
            length = int(m.get("length", 0))
            if length <= 0 or off < 0 or off + length > len(text):
                filtered.append(m); continue
            token = text[off:off+length].strip().lower()
            if token in allow:
                continue
            filtered.append(m)
        except Exception:
            filtered.append(m)
    return filtered

async def call_llm(messages: List[dict], temperature=0.4, max_tokens=220) -> tuple[bool, str, str | None]:
    payload_openai = {"model": MODEL_NAME, "messages": messages, "temperature": temperature, "max_tokens": max_tokens}
    payload_ollama = {"model": MODEL_NAME, "messages": messages, "stream": False, "options": {"temperature": temperature}}

    async with httpx.AsyncClient(timeout=120) as client:
        try:
            r = await client.post(LLM_URLS[0], json=payload_openai)
            if r.status_code == 200:
                j = r.json()
                choice = (j.get("choices") or [{}])[0]
                content = choice.get("message", {}).get("content") or choice.get("text") or ""
                return True, content.strip(), None
        except Exception:
            pass
        try:
            r = await client.post(LLM_URLS[1], json=payload_ollama)
            r.raise_for_status()
            j = r.json()
            msg = j.get("message") or {}
            content = msg.get("content", "")
            return True, content.strip(), None
        except Exception as e:
            return False, "", str(e)

def readability_es(text: str) -> dict:
    text = _normalize_spaces(text)
    sents = textstat.sentence_count(text)
    words = textstat.lexicon_count(text, removepunct=True)
    syll = textstat.syllable_count(text)
    flesch = textstat.flesch_reading_ease(text)
    return {"sentences": sents, "words": words, "syllables": syll, "flesch_en_reference": flesch}

# ───────────────────── Correcciones ─────────────────────
SAFE_REGEX = [
    (re.compile(r"\s+([,.;:!?])"), r"\1"),
    (re.compile(r"([¿¡\(\[])\s+"), r"\1"),
    (re.compile(r"[ \t]{2,}"), " "),
    (re.compile(r"[ \t]+(\n)"), r"\1"),
]

def apply_safe(text: str) -> tuple[str, int]:
    text = _normalize_spaces(text)
    applied = 0
    for r in (ES_MX.get("espacios") or []):
        try:
            rgx = re.compile(r.get("regex", ""))
        except re.error:
            continue
        repl = r.get("replace", "")
        text, n = rgx.subn(repl, text)
        applied += n
    for rgx, repl in SAFE_REGEX:
        text, n = rgx.subn(repl, text)
        applied += n
    return text, applied

def apply_lt_replacements(text: str, matches: list, rule_filter: Optional[set] = None) -> tuple[str, int]:
    text = _normalize_spaces(text)
    mlist = [m for m in matches if (m.get("replacements") and (not rule_filter or m.get("rule") in rule_filter))]
    allow = set(w.lower() for w in DICT)
    safe_list = []
    for m in mlist:
        off = int(m.get("offset", 0))
        length = int(m.get("length", 0))
        if 0 <= off and off + length <= len(text):
            token = text[off:off+length].strip().lower()
            if token in allow:
                continue
        safe_list.append(m)

    ms = sorted(safe_list, key=lambda m: int(m.get("offset", 0)))
    applied = 0
    delta = 0
    t = text
    for m in ms:
        off = int(m.get("offset", 0)) + delta
        length = int(m.get("length", 0))
        repl = str(m.get("replacements", [""])[0])
        if off < 0 or off + length > len(t):
            continue
        t = t[:off] + repl + t[off+length:]
        delta += len(repl) - length
        applied += 1
    return t, applied

def make_unified_diff(a: str, b: str) -> str:
    da = a.splitlines(keepends=True)
    db = b.splitlines(keepends=True)
    diff = difflib.unified_diff(da, db, fromfile="original", tofile="corregido", n=0)
    return "".join(diff)

# ───────────────────── RAG: carga índice ─────────────────────
_FAISS = None
_META  = None
_EMB_MODEL = None

def _ensure_index() -> bool:
    global _FAISS, _META, _EMB_MODEL
    if _FAISS is not None and _META is not None and _EMB_MODEL is not None:
        return True
    if not FAISS_INDEX_PATH.exists() or not FAISS_META_PATH.exists():
        return False
    import faiss
    from sentence_transformers import SentenceTransformer
    _FAISS = faiss.read_index(str(FAISS_INDEX_PATH))
    _META = json.loads(FAISS_META_PATH.read_text(encoding="utf-8"))
    _EMB_MODEL = SentenceTransformer(EMB_MODEL)
    return True

def retrieve(query: str, k: int = 4) -> list[dict]:
    if not _ensure_index():
        return []
    qv = _EMB_MODEL.encode([query], convert_to_numpy=True, normalize_embeddings=True)
    D, I = _FAISS.search(qv, k)
    out = []
    txt_dir = BASE_DIR / "data" / "corpus_txt"
    cache: dict[str, str] = {}
    metas = _META
    for idx in I[0]:
        if idx == -1:
            continue
        m = metas[idx]
        src = m["source"]
        if src not in cache:
            fp = txt_dir / src
            cache[src] = fp.read_text(encoding="utf-8", errors="ignore")
        text = cache[src]
        out.append({"source": src, "chunk_id": m["chunk_id"], "text": text})
    return out[:k]

# ───────────────────── Schemas ─────────────────────
class TextIn(BaseModel):
    text: str
    lang: Optional[str] = "es"   # permite 'en', 'es-419', etc.

class ApplyIn(BaseModel):
    text: str
    mode: str = "safe"           # "safe" | "all" | "rules"
    rules: Optional[List[str]] = None

# ───────────────────── Endpoints básicos ─────────────────────
@app.get("/health")
async def health():
    lt = await languagetool_check("Esto es una prueba de LanguageTool.")
    ok_llm, _, err_llm = await call_llm(
        [{"role": "user", "content": "Di 'ok' si recibes este mensaje."}],
        temperature=0.1, max_tokens=5
    )
    return {
        "spaCy": nlp is not None,
        "LanguageTool": lt.get("ok"),
        "LLM": ok_llm,
        "rules_loaded": bool(ES_MX),
        "lt_error": lt.get("error"),
        "llm_error": err_llm,
    }

@app.post("/analyze_text")
async def analyze_text_ep(data: TextIn):
    text = _normalize_spaces(data.text)
    lang = (data.lang or "es").strip()

    lt = await languagetool_check(text, lang=lang)
    matches = filter_matches_by_dictionary(text, lt.get("matches") or [])

    # Reglas locales (solo para español)
    if lang.lower().startswith("es"):
        matches += apply_es_mx(text)

    stats = spacy_stats(text)
    readab = readability_es(text)
    return {
        "languageTool": {"ok": lt.get("ok"), "matches": matches},
        "stats": stats,
        "readability": readab,
        "text": text,
        "lang": lang,
    }

@app.post("/analyze_file")
async def analyze_file_ep(file: UploadFile = File(...), lang: str = "es"):
    content = await file.read()
    text = _normalize_spaces(read_any(content, file.filename))

    lt = await languagetool_check(text, lang=lang)
    matches = filter_matches_by_dictionary(text, lt.get("matches") or [])
    if lang.lower().startswith("es"):
        matches += apply_es_mx(text)

    stats = spacy_stats(text)
    readab = readability_es(text)
    return {
        "filename": file.filename,
        "languageTool": {"ok": lt.get("ok"), "matches": matches},
        "stats": stats,
        "readability": readab,
        "text": text,
        "lang": lang,
    }

@app.post("/suggest")
async def suggest_ep(data: TextIn):
    msgs = [
        {"role": "system",
         "content": "Eres un editor de estilo literario en español (México). Mejora claridad, ritmo y concisión SIN cambiar el significado ni la voz."},
        {"role": "user", "content": f"Reescribe el siguiente párrafo manteniendo el tono:\n\n{data.text}"},
    ]
    ok, content, err = await call_llm(msgs, temperature=0.4, max_tokens=220)
    return {"ok": ok, "suggestion": content, "error": err}

@app.post("/suggest_with_refs")
async def suggest_with_refs(data: TextIn):
    ctxs = retrieve(data.text, k=4)
    ctx_text = "\n\n".join([
        f"[{i+1}] {c['source']} (fragmento {c['chunk_id']}):\n{c['text'][:1200]}"
        for i, c in enumerate(ctxs)
    ])
    prompt = (
        "Eres un editor de estilo literario en español (México). Mejora el párrafo manteniendo el tono.\n"
        "Usa la guía y ejemplos de referencia (si son relevantes) solo como orientación estilística, no copies literalmente.\n\n"
        f"REFERENCIAS:\n{ctx_text}\n\n"
        f"TEXTO:\n{data.text}\n\n"
        "Responde con una propuesta clara y pulida."
    )
    msgs = [
        {"role": "system", "content": "Editor de estilo para español de México."},
        {"role": "user", "content": prompt},
    ]
    ok, content, err = await call_llm(msgs, temperature=0.4, max_tokens=260)
    return {"ok": ok, "suggestion": content, "error": err, "citations": ctxs}

@app.post("/apply_lt")
async def apply_lt(ep: ApplyIn):
    original = _normalize_spaces(ep.text)
    if ep.mode == "safe":
        new_text, applied = apply_safe(original)
    else:
        lt = await languagetool_check(original)
        matches = filter_matches_by_dictionary(original, lt.get("matches") or [])
        rule_filter = set(ep.rules or []) if ep.mode == "rules" else None
        new_text, applied = apply_lt_replacements(original, matches, rule_filter=rule_filter)
    diff = make_unified_diff(original, new_text)
    return {"applied": int(applied), "new_text": new_text, "diff": diff}

# ───────────── Alias de compatibilidad ─────────────
@app.post("/analyze/text")
async def analyze_text_alias(data: TextIn):
    return await analyze_text_ep(data)

@app.post("/analyze/file")
async def analyze_file_alias(file: UploadFile = File(...), lang: str = "es"):
    return await analyze_file_ep(file, lang=lang)

class _ApplySafeIn(BaseModel):
    text: str

@app.post("/apply/safe")
async def apply_safe_alias(data: _ApplySafeIn):
    return await apply_lt(ApplyIn(text=data.text, mode="safe"))

class _ApplyAllIn(BaseModel):
    text: str

@app.post("/apply/all")
async def apply_all_alias(data: _ApplyAllIn):
    return await apply_lt(ApplyIn(text=data.text, mode="all"))

# ───────────── Diccionario endpoints ─────────────
@app.get("/dictionary/list")
def dictionary_list(lang: str = "es"):
    return {"words": sorted(list(DICT))}

class _DictIn(BaseModel):
    token: str
    lang: str = "es"

@app.post("/dictionary/add")
def dictionary_add(item: _DictIn):
    token = (item.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token vacío")
    DICT.add(token.lower())
    return {"ok": True}

@app.post("/dictionary/remove")
def dictionary_remove(item: _DictIn):
    token = (item.token or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token vacío")
    DICT.discard(token.lower())
    return {"ok": True}

# ───────────── Utilidades de mantenimiento ─────────────
@app.post("/refresh_corpus")
async def refresh_corpus():
    py = sys.executable
    try:
        r1 = subprocess.run([py, str(BASE_DIR / "tools" / "pdf_to_txt.py")], capture_output=True, text=True)
        r2 = subprocess.run([py, str(BASE_DIR / "tools" / "build_index.py")], capture_output=True, text=True)
        global _FAISS, _META, _EMB_MODEL
        _FAISS = _META = _EMB_MODEL = None
        return {"ok": True, "pdf_to_txt": r1.stdout + r1.stderr, "build_index": r2.stdout + r2.stderr}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@app.post("/reload_rules")
async def reload_rules():
    load_es_mx()
    return {"ok": True, "rules_loaded": bool(ES_MX)}

# ───── DOCX preservando formato (análisis + aplicación) ─────
_DOCX_SESSIONS: dict[str, dict] = {}

def docx_to_text_and_map(doc) -> tuple[str, list]:
    text_parts: list[str] = []
    mapping: list[dict] = []
    abs_pos = 0
    for p_idx, p in enumerate(doc.paragraphs):
        runs_map = []
        para_start = abs_pos
        for r_idx, r in enumerate(p.runs):
            t = r.text or ""
            start = abs_pos
            end = start + len(t)
            runs_map.append({"r_idx": r_idx, "start": start, "end": end})
            text_parts.append(t)
            abs_pos = end
        text_parts.append("\n")
        abs_pos += 1
        mapping.append({"p_idx": p_idx, "runs": runs_map, "abs_start": para_start, "abs_end": abs_pos})
    full_text = "".join(text_parts)
    return full_text, mapping

def apply_replacements_to_docx(doc, mapping, edits, original_full_text):
    edits_sorted = sorted(edits, key=lambda e: e["offset"], reverse=True)
    for e in edits_sorted:
        off = int(e["offset"]); length = int(e["length"]); repl = str(e["replacement"])
        end_off = off + length
        applied = False
        for m in mapping:
            if off < m["abs_start"] or end_off > m["abs_end"]:
                continue
            for rinfo in m["runs"]:
                if off >= rinfo["start"] and end_off <= rinfo["end"]:
                    p = doc.paragraphs[m["p_idx"]]
                    r = p.runs[rinfo["r_idx"]]
                    local_start = off - rinfo["start"]
                    local_end = end_off - rinfo["start"]
                    r.text = (r.text or "")[:local_start] + repl + (r.text or "")[local_end:]
                    applied = True
                    break
            if applied:
                break
    return doc

def build_edits_from_matches(matches, mode="lt_all", base_text: Optional[str] = None):
    if mode == "safe":
        return []
    edits = []
    allow = set(w.lower() for w in DICT)
    for m in matches:
        reps = m.get("replacements") or []
        if not reps:
            continue
        off = int(m.get("offset", 0))
        length = int(m.get("length", 0))
        if base_text and 0 <= off and off + length <= len(base_text):
            token = base_text[off:off+length].strip().lower()
            if token in allow:
                continue
        edits.append({"offset": off, "length": length, "replacement": str(reps[0])})
    return edits

@app.post("/analyze_docx_preserving")
async def analyze_docx_preserving(file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".docx"):
        raise HTTPException(status_code=400, detail="Sube un archivo .docx")

    content = await file.read()
    doc = docx.Document(io.BytesIO(content))
    full_text, mapping = docx_to_text_and_map(doc)
    full_text_norm = _normalize_spaces(full_text)

    lt = await languagetool_check(full_text_norm)
    matches = filter_matches_by_dictionary(full_text_norm, lt.get("matches") or [])
    matches += apply_es_mx(full_text_norm)

    session_id = str(uuid.uuid4())
    _DOCX_SESSIONS[session_id] = {
        "doc_bytes": content,
        "mapping": mapping,
        "full_text": full_text,
        "filename": file.filename,
    }

    return {
        "session_id": session_id,
        "text": full_text,
        "languageTool": {"ok": lt.get("ok"), "matches": matches},
    }

class ApplyDocxIn(BaseModel):
    session_id: str
    mode: str = "lt_all"  # "lt_all" | "safe"
    edits: Optional[List[dict]] = None

@app.post("/apply_docx_preserving")
async def apply_docx_preserving(data: ApplyDocxIn):
    sess = _DOCX_SESSIONS.get(data.session_id)
    if not sess:
        raise HTTPException(status_code=404, detail="session_id no válido o expirado")

    doc = docx.Document(io.BytesIO(sess["doc_bytes"]))
    mapping = sess["mapping"]
    original_full_text = sess["full_text"]

    edits = data.edits
    if edits is None:
        lt = await languagetool_check(_normalize_spaces(original_full_text))
        matches = filter_matches_by_dictionary(original_full_text, lt.get("matches") or [])
        matches += apply_es_mx(original_full_text)
        edits = build_edits_from_matches(matches, mode=data.mode, base_text=original_full_text)

    doc = apply_replacements_to_docx(doc, mapping, edits, original_full_text)

    bio = io.BytesIO()
    doc.save(bio)
    bio.seek(0)
    outname = "manuscrito_editado.docx"
    return StreamingResponse(
        bio,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f'attachment; filename="{outname}"'},
    )
