# tools/pdf_to_txt.py
import os
from pathlib import Path
from pypdf import PdfReader

BASE = Path(__file__).resolve().parents[1]
RAW = BASE / "data" / "corpus_raw"
TXT = BASE / "data" / "corpus_txt"
TXT.mkdir(parents=True, exist_ok=True)

def pdf_to_txt(pdf_path: Path, out_dir: Path):
    name = pdf_path.stem
    out_file = out_dir / f"{name}.txt"
    try:
        reader = PdfReader(str(pdf_path))
        pages = []
        for i, p in enumerate(reader.pages):
            try:
                pages.append(p.extract_text() or "")
            except Exception:
                pages.append("")
        out_file.write_text("\n\n".join(pages), encoding="utf-8", errors="ignore")
        print(f"[OK] {pdf_path.name} -> {out_file.name}")
    except Exception as e:
        print(f"[ERR] {pdf_path.name}: {e}")

def main():
    for pdf in sorted(RAW.glob("*.pdf")):
        pdf_to_txt(pdf, TXT)

if __name__ == "__main__":
    main()
