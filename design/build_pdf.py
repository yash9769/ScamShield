#!/usr/bin/env python3
"""Renders design/scamshield_ui.html to a print-ready PDF.

The app's own Inter faces (assets/fonts, SIL OFL) are inlined as base64 so the
document is set in the same typeface the app ships — a design spec typeset in
a substitute font misrepresents the thing it is specifying.

Usage:  python3 design/build_pdf.py
"""

import base64
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML_IN = ROOT / "design" / "scamshield_ui.html"
HTML_TMP = ROOT / "design" / ".scamshield_ui.embedded.html"
PDF_OUT = ROOT / "design" / "ScamShield-UI-Redesign.pdf"
FONT_DIR = ROOT / "assets" / "fonts"

# Chromium ships with the Playwright browsers in this environment; fall back to
# whatever is on PATH so the script still works on a normal machine.
CHROME_CANDIDATES = [
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/opt/pw-browsers/chromium/chrome-linux/chrome",
    "chromium",
    "chromium-browser",
    "google-chrome",
]

FACES = [
    ("Inter-Regular.ttf", 400),
    ("Inter-Medium.ttf", 500),
    ("Inter-SemiBold.ttf", 600),
    ("Inter-Bold.ttf", 700),
]


def font_face_css() -> str:
    blocks = []
    for filename, weight in FACES:
        path = FONT_DIR / filename
        if not path.exists():
            print(f"  ! missing {path.name}, falling back to system sans", file=sys.stderr)
            continue
        b64 = base64.b64encode(path.read_bytes()).decode("ascii")
        blocks.append(
            "@font-face{font-family:'Inter';font-style:normal;"
            f"font-weight:{weight};font-display:block;"
            f"src:url(data:font/ttf;base64,{b64}) format('truetype');}}"
        )
    return "\n".join(blocks)


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if candidate.startswith("/"):
            if pathlib.Path(candidate).exists():
                return candidate
        else:
            from shutil import which
            found = which(candidate)
            if found:
                return found
    raise SystemExit("No Chromium/Chrome binary found — cannot render the PDF.")


def main() -> None:
    html = HTML_IN.read_text(encoding="utf-8")
    html = html.replace("/* __FONT_FACE__ */", font_face_css())
    HTML_TMP.write_text(html, encoding="utf-8")

    chrome = find_chrome()
    print(f"  · rendering with {chrome}")
    subprocess.run(
        [
            chrome,
            "--headless",
            "--disable-gpu",
            "--no-sandbox",
            "--no-pdf-header-footer",
            # The page rule in the HTML is 794×1123 (A4 at 96dpi); letting
            # Chromium scale to its own default paper would reflow every
            # carefully-sized mockup.
            "--print-to-pdf-no-header",
            f"--print-to-pdf={PDF_OUT}",
            HTML_TMP.as_uri(),
        ],
        check=True,
        capture_output=True,
    )

    HTML_TMP.unlink(missing_ok=True)
    size_kb = PDF_OUT.stat().st_size / 1024
    print(f"  ✓ {PDF_OUT.relative_to(ROOT)} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
