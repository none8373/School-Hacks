#!/usr/bin/env python3
"""Print the text of PDF (or plain-text) files, one after another, with page markers."""
import sys
from pathlib import Path

for arg in sys.argv[1:]:
    path = Path(arg)
    print(f"===== FILE: {path.name} =====")
    if path.suffix.lower() == ".pdf":
        from pypdf import PdfReader
        for i, page in enumerate(PdfReader(str(path)).pages):
            print(f"[page {i + 1}]")
            print(page.extract_text() or "")
    else:
        print(path.read_text(errors="replace"))
