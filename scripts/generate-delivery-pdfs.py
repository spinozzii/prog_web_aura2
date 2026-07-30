#!/usr/bin/env python3
"""Generate the two delivery PDFs from their reviewed Markdown sources."""

from __future__ import annotations

import re
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    ListFlowable,
    ListItem,
    PageTemplate,
    Paragraph,
    Spacer,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf"
BLUE = colors.HexColor("#174A74")
LIGHT_BLUE = colors.HexColor("#EAF3F8")
INK = colors.HexColor("#202B33")
MUTED = colors.HexColor("#5B6870")


def register_fonts() -> tuple[str, str, str]:
    fonts = Path("C:/Windows/Fonts")
    regular = fonts / "arial.ttf"
    bold = fonts / "arialbd.ttf"
    mono = fonts / "consola.ttf"
    if regular.is_file() and bold.is_file() and mono.is_file():
        pdfmetrics.registerFont(TTFont("DriveAuraSans", str(regular)))
        pdfmetrics.registerFont(TTFont("DriveAuraSansBold", str(bold)))
        pdfmetrics.registerFont(TTFont("DriveAuraMono", str(mono)))
        return "DriveAuraSans", "DriveAuraSansBold", "DriveAuraMono"
    return "Helvetica", "Helvetica-Bold", "Courier"


FONT, FONT_BOLD, FONT_MONO = register_fonts()


class DeliveryDocument(BaseDocTemplate):
    def __init__(self, filename: Path, *, compact: bool, title: str) -> None:
        margin = 16 * mm if compact else 19 * mm
        super().__init__(
            str(filename),
            pagesize=A4,
            leftMargin=margin,
            rightMargin=margin,
            topMargin=17 * mm,
            bottomMargin=16 * mm,
            title=title,
            author="Drive Aura 51",
            subject="Secondo progetto di Programmazione Web - scelta B",
        )
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            id="normal",
        )
        self.addPageTemplates(
            PageTemplate(id="delivery", frames=frame, onPage=self.draw_page)
        )

    def draw_page(self, canvas, doc) -> None:
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor("#CBD6DC"))
        canvas.setLineWidth(0.5)
        canvas.line(
            self.leftMargin,
            12.5 * mm,
            A4[0] - self.rightMargin,
            12.5 * mm,
        )
        canvas.setFont(FONT, 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(self.leftMargin, 8.5 * mm, "Drive Aura 51 - scelta B")
        canvas.drawRightString(
            A4[0] - self.rightMargin,
            8.5 * mm,
            f"Pagina {doc.page}",
        )
        canvas.restoreState()


def inline_markup(text: str) -> str:
    pieces: list[str] = []
    cursor = 0
    for match in re.finditer(r"`([^`]+)`", text):
        pieces.append(escape(text[cursor : match.start()]))
        pieces.append(
            f'<font name="{FONT_MONO}" color="#174A74">'
            f"{escape(match.group(1))}</font>"
        )
        cursor = match.end()
    pieces.append(escape(text[cursor:]))
    value = "".join(pieces)
    value = re.sub(r"\*\*([^*]+)\*\*", rf'<font name="{FONT_BOLD}">\1</font>', value)
    return value


def make_styles(*, compact: bool) -> dict[str, ParagraphStyle]:
    samples = getSampleStyleSheet()
    body_size = 8.45 if compact else 9.4
    leading = 10.45 if compact else 12.2
    return {
        "title": ParagraphStyle(
            "Title",
            parent=samples["Title"],
            fontName=FONT_BOLD,
            fontSize=19 if compact else 23,
            leading=22 if compact else 27,
            textColor=BLUE,
            alignment=TA_LEFT,
            spaceAfter=6 * mm,
        ),
        "h2": ParagraphStyle(
            "Heading2",
            parent=samples["Heading2"],
            fontName=FONT_BOLD,
            fontSize=10.7 if compact else 13.2,
            leading=12.5 if compact else 15.5,
            textColor=BLUE,
            spaceBefore=3.5 * mm if compact else 5 * mm,
            spaceAfter=1.5 * mm,
            keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "Heading3",
            parent=samples["Heading3"],
            fontName=FONT_BOLD,
            fontSize=9.1 if compact else 10.1,
            leading=11 if compact else 12.2,
            textColor=colors.HexColor("#2F5F7D"),
            spaceBefore=2.3 * mm,
            spaceAfter=1 * mm,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=samples["BodyText"],
            fontName=FONT,
            fontSize=body_size,
            leading=leading,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=1.8 * mm if compact else 2.5 * mm,
            splitLongWords=True,
        ),
        "lead": ParagraphStyle(
            "Lead",
            parent=samples["BodyText"],
            fontName=FONT,
            fontSize=9.1 if compact else 10.4,
            leading=11.3 if compact else 13.4,
            textColor=MUTED,
            spaceAfter=3 * mm,
        ),
        "list": ParagraphStyle(
            "List",
            parent=samples["BodyText"],
            fontName=FONT,
            fontSize=body_size,
            leading=leading,
            textColor=INK,
            leftIndent=1 * mm,
            spaceAfter=0.7 * mm,
        ),
        "code": ParagraphStyle(
            "Code",
            parent=samples["Code"],
            fontName=FONT_MONO,
            fontSize=7.25 if compact else 7.7,
            leading=9.1 if compact else 9.8,
            textColor=colors.HexColor("#19323F"),
            backColor=LIGHT_BLUE,
            borderColor=colors.HexColor("#C7DCE8"),
            borderWidth=0.5,
            borderPadding=5,
            leftIndent=0,
            rightIndent=0,
            spaceBefore=1.5 * mm,
            spaceAfter=3 * mm,
            splitLongWords=True,
        ),
    }


def parse_markdown(path: Path, *, compact: bool) -> list:
    styles = make_styles(compact=compact)
    lines = path.read_text(encoding="utf-8").splitlines()
    story: list = []
    paragraph: list[str] = []
    code: list[str] = []
    list_items: list[str] = []
    list_kind: str | None = None
    in_code = False
    body_seen = False

    def flush_paragraph() -> None:
        nonlocal paragraph, body_seen
        if paragraph:
            text = " ".join(item.strip() for item in paragraph)
            style = styles["lead"] if not body_seen else styles["body"]
            story.append(Paragraph(inline_markup(text), style))
            paragraph = []
            body_seen = True

    def flush_list() -> None:
        nonlocal list_items, list_kind
        if not list_items:
            return
        items = [
            ListItem(Paragraph(inline_markup(item), styles["list"]))
            for item in list_items
        ]
        options = {
            "bulletType": "1" if list_kind == "number" else "bullet",
            "leftIndent": 5 * mm,
            "bulletFontName": FONT_BOLD,
            "bulletFontSize": 8,
            "bulletColor": BLUE,
            "spaceAfter": 2 * mm,
        }
        if list_kind == "number":
            options["start"] = "1"
        story.append(ListFlowable(items, **options))
        list_items = []
        list_kind = None

    for raw in lines + [""]:
        line = raw.rstrip()
        if line.startswith("```"):
            flush_paragraph()
            flush_list()
            if in_code:
                safe_lines = [escape(item).replace(" ", "&#160;") for item in code]
                story.append(Paragraph("<br/>".join(safe_lines), styles["code"]))
                code = []
                in_code = False
            else:
                in_code = True
            continue
        if in_code:
            code.append(line)
            continue
        if not line.strip():
            flush_paragraph()
            flush_list()
            continue
        if line.startswith("# "):
            flush_paragraph()
            flush_list()
            story.append(Paragraph(inline_markup(line[2:].strip()), styles["title"]))
            continue
        if line.startswith("## "):
            flush_paragraph()
            flush_list()
            story.append(Paragraph(inline_markup(line[3:].strip()), styles["h2"]))
            continue
        if line.startswith("### "):
            flush_paragraph()
            flush_list()
            story.append(Paragraph(inline_markup(line[4:].strip()), styles["h3"]))
            continue
        bullet = re.match(r"^-\s+(.+)$", line)
        numbered = re.match(r"^\d+\.\s+(.+)$", line)
        if bullet or numbered:
            flush_paragraph()
            current_kind = "bullet" if bullet else "number"
            if list_kind is not None and list_kind != current_kind:
                flush_list()
            list_kind = current_kind
            list_items.append((bullet or numbered).group(1))
            continue
        flush_list()
        paragraph.append(line)

    return story


def build(source: Path, destination: Path, *, compact: bool, title: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    document = DeliveryDocument(destination, compact=compact, title=title)
    story = parse_markdown(source, compact=compact)
    if not story:
        raise RuntimeError(f"Documento vuoto: {source}")
    document.build(story)


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    build(
        ROOT / "docs" / "MANUALE_INSTALLAZIONE.md",
        OUTPUT / "manuale-drive-aura-51.pdf",
        compact=True,
        title="Drive Aura 51 - Manuale di installazione",
    )
    build(
        ROOT / "docs" / "SCELTE_PROGETTO.md",
        OUTPUT / "scelte-progettuali-drive-aura-51.pdf",
        compact=True,
        title="Drive Aura 51 - Scelte progettuali",
    )
    for path in sorted(OUTPUT.glob("*.pdf")):
        print(f"{path.name}: {path.stat().st_size} byte")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
