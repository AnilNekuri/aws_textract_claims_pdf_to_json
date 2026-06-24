from pathlib import Path


OUTPUT_PATH = Path(__file__).resolve().parents[1] / "sample-claim.pdf"


def pdf_escape(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def text_line(x, y, text, size=11):
    return f"BT /F1 {size} Tf {x} {y} Td ({pdf_escape(text)}) Tj ET"


def build_pdf():
    lines = [
        (72, 740, "SYNTHETIC HEALTH CLAIM FORM", 16),
        (72, 710, "Claim Number: CLM-2026-000123", 11),
        (72, 692, "Member ID: M12345", 11),
        (72, 674, "Patient Name: John Smith", 11),
        (72, 656, "Provider Name: ABC Provider Clinic", 11),
        (72, 638, "Date of Service: 01/15/2026", 11),
        (72, 620, "Total Billed Amount: $500.00", 11),
        (72, 602, "Total Paid Amount: $300.00", 11),
        (72, 566, "SERVICE LINES", 13),
        (72, 542, "Date of Service | Procedure Code | Units | Billed Amount | Allowed Amount | Paid Amount", 9),
        (72, 524, "01/15/2026 | 99213 | 1 | $500.00 | $350.00 | $300.00", 9),
        (72, 488, "Notes: This is a synthetic document for AWS Textract POC testing only.", 10),
        (72, 470, "It does not contain real patient, provider, member, or claim information.", 10),
    ]

    content = "\n".join(text_line(*line) for line in lines)
    content_bytes = content.encode("latin-1")

    objects = []

    def add_object(body):
        objects.append(body)
        return len(objects)

    pages_id = add_object("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    font_id = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    page_id = add_object(
        f"<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 612 792] "
        f"/Resources << /Font << /F1 {font_id} 0 R >> >> /Contents 4 0 R >>"
    )
    content_id = add_object(
        f"<< /Length {len(content_bytes)} >>\nstream\n{content}\nendstream"
    )
    catalog_id = add_object(f"<< /Type /Catalog /Pages {pages_id} 0 R >>")

    assert page_id == 3
    assert content_id == 4
    assert catalog_id == 5

    pdf = bytearray()
    pdf.extend(b"%PDF-1.4\n")
    offsets = [0]

    for index, body in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf.extend(f"{index} 0 obj\n{body}\nendobj\n".encode("latin-1"))

    xref_offset = len(pdf)
    pdf.extend(f"xref\n0 {len(objects) + 1}\n".encode("latin-1"))
    pdf.extend(b"0000000000 65535 f \n")

    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode("latin-1"))

    pdf.extend(
        (
            "trailer\n"
            f"<< /Size {len(objects) + 1} /Root {catalog_id} 0 R >>\n"
            "startxref\n"
            f"{xref_offset}\n"
            "%%EOF\n"
        ).encode("latin-1")
    )

    return bytes(pdf)


def main():
    OUTPUT_PATH.write_bytes(build_pdf())
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
