#!/usr/bin/env python3
"""Pull text out of lecture slide PDFs, so sample decks can be written from real source material.

This is provenance, not a feature. Elbert does not read PDFs on device: turning documents into
cards is a wave-2 server round trip (`api/generate.ts`), because the Anthropic key cannot ship
inside an .ipa. This script exists so the sample decks in Resources/SampleDecks.json can be traced
back to the slides they came from, and rebuilt if those slides change.

    python3 -m venv .venv && .venv/bin/pip install pypdf
    .venv/bin/python ios/Tools/extract-slides.py "~/Desktop/SMU/Past Sems/Y2S1/Marketing" out.json

The output is raw slide text. Writing the cards from it is a human job: a slide bullet is not a
flashcard, and a deck of auto-split bullets is how you end up reviewing sentence fragments.
"""

import json
import os
import re
import sys

try:
    from pypdf import PdfReader
except ImportError:
    sys.exit("pypdf is not installed. See the module docstring.")

MIN_PAGE_CHARS = 40


def slide_text(path: str) -> list[str]:
    """Every page of a PDF that carries enough text to be worth reading.

    Slide decks are mostly images with a little text on top, so pages that extract to almost
    nothing are normal and are dropped rather than reported as failures.
    """
    reader = PdfReader(path)
    pages = []
    for page in reader.pages:
        text = re.sub(r"\n{2,}", "\n", page.extract_text() or "").strip()
        if len(text) >= MIN_PAGE_CHARS:
            pages.append(text)
    return pages


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(f"usage: {os.path.basename(sys.argv[0])} <folder-of-pdfs> <output.json>")

    folder = os.path.expanduser(sys.argv[1])
    out_path = os.path.expanduser(sys.argv[2])

    documents = []
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith(".pdf"):
            continue
        path = os.path.join(folder, name)
        try:
            pages = slide_text(path)
        except Exception as error:  # a malformed PDF should not stop the rest
            print(f"skipped {name}: {error}", file=sys.stderr)
            continue
        documents.append({"file": name, "pages": pages})
        print(f"{name}: {len(pages)} pages with text")

    with open(out_path, "w") as handle:
        json.dump({"source": folder, "documents": documents}, handle, indent=2)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
