"""Creates demo.pdf used by the PDFist function smoke test."""
from fpdf import FPDF

pdf = FPDF()
pdf.set_margins(20, 20, 20)

# ── Page 1: Text + headings ───────────────────────────────────────────────────
pdf.add_page()
pdf.set_font("Helvetica", "B", 24)
pdf.cell(0, 12, "PDFist Demo Document", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
pdf.cell(0, 8, "Author: Test User   |   Subject: QA Demo   |   Keywords: pdf test",
         new_x="LMARGIN", new_y="NEXT")
pdf.ln(4)
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 8, "Section 1 - Introduction", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
body = (
    "This document is used to smoke-test every PDF tool in PDFist. "
    "It contains multiple pages, varied text, and form fields so that "
    "compress, rotate, split, watermark, stamp, header-footer, word-count, "
    "find-replace, text markup, bookmarks, metadata editing, and many other "
    "operations all have real content to work with.\n\n"
    "The quick brown fox jumps over the lazy dog. "
    "Pack my box with five dozen liquor jugs. "
    "How vexingly quick daft zebras jump! "
    "The five boxing wizards jump quickly."
)
pdf.multi_cell(0, 6, body)
pdf.ln(4)
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 8, "Section 2 - Numbers and Data", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
for i in range(1, 9):
    pdf.cell(0, 6, f"Row {i:02d}: value={i*7:4d}  label=item_{i:02d}  status={'OK' if i%2==0 else 'PENDING'}",
             new_x="LMARGIN", new_y="NEXT")

# ── Page 2: More body text ────────────────────────────────────────────────────
pdf.add_page()
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 8, "Section 3 - Lorem Ipsum", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
lorem = (
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris. "
    "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum. "
    "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia "
    "deserunt mollit anim id est laborum.\n\n"
    "Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. "
    "Nullam varius, turpis molestie dictum semper, ex quam pharetra ipsum, "
    "ut condimentum nibh nunc sit amet massa. "
    "FIND_THIS_TEXT is a placeholder that will be replaced in the find-replace test. "
    "Another FIND_THIS_TEXT occurrence appears here for completeness."
)
pdf.multi_cell(0, 6, lorem)
pdf.ln(4)
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 8, "Section 4 - Contact", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
pdf.cell(0, 6, "Email: demo@pdfist.app", new_x="LMARGIN", new_y="NEXT")
pdf.cell(0, 6, "Website: https://pdfist.app", new_x="LMARGIN", new_y="NEXT")
pdf.cell(0, 6, "Phone: +1 (555) 000-1234", new_x="LMARGIN", new_y="NEXT")

# ── Page 3: Table-like data ───────────────────────────────────────────────────
pdf.add_page()
pdf.set_font("Helvetica", "B", 14)
pdf.cell(0, 8, "Section 5 - Invoice", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "B", 11)
pdf.cell(80, 7, "Item", border=1)
pdf.cell(40, 7, "Qty", border=1, align="C")
pdf.cell(40, 7, "Price", border=1, align="C")
pdf.cell(0, 7, "Total", border=1, align="C", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Helvetica", "", 11)
items = [
    ("PDF Compress License", 1, 29.99),
    ("PDF Merge License", 2, 19.99),
    ("PDF OCR License", 1, 49.99),
    ("Support Pack", 12, 9.99),
]
for name, qty, price in items:
    pdf.cell(80, 6, name, border=1)
    pdf.cell(40, 6, str(qty), border=1, align="C")
    pdf.cell(40, 6, f"${price:.2f}", border=1, align="C")
    pdf.cell(0, 6, f"${qty*price:.2f}", border=1, align="C", new_x="LMARGIN", new_y="NEXT")

# ── Page 4: Final page ────────────────────────────────────────────────────────
pdf.add_page()
pdf.set_font("Helvetica", "B", 18)
pdf.cell(0, 10, "End of Document", new_x="LMARGIN", new_y="NEXT", align="C")
pdf.set_font("Helvetica", "", 11)
pdf.ln(6)
pdf.multi_cell(0, 6,
    "This is page 4 of 4. If you see this page after a split or extract "
    "operation it confirms the page-range logic is working correctly. "
    "Word count, character count, and other analysis tools should report "
    "accurate statistics across all four pages of this document.")

# ── Metadata ──────────────────────────────────────────────────────────────────
pdf.set_title("PDFist Demo Document")
pdf.set_author("Test User")
pdf.set_subject("QA Smoke Test")
pdf.set_keywords("pdf test demo pdfist")
pdf.set_creator("PDFist create_demo.py")

out = "tool/demo.pdf"
pdf.output(out)
print(f"Created {out}  ({pdf.pages} pages)")
