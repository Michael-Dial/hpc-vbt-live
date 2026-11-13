"""Build the print sheets for the bar-end tag mount (throwaway probe).

Reads the one-pixel-per-cell tag images in tags/ and writes bar-end-tags.pdf:
US Letter pages meant to be printed at 100% scale. Pure standard library.

    python3 -I make_sheets.py
"""
import struct
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
MM = 72 / 25.4  # points per millimetre
PAGE_W, PAGE_H = 612, 792  # US Letter, points


def read_cells(path):
    """Return rows of booleans (True = black) from an 8-bit RGBA PNG."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat, head = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, depth, colour, _, _, interlace = head
    assert (depth, colour, interlace) == (8, 6, 0), f"{path}: unexpected PNG format {head}"
    raw = zlib.decompress(idat)
    stride = width * 4
    rows, prev = [], bytes(stride)
    for y in range(height):
        line = raw[y * (stride + 1):(y + 1) * (stride + 1)]
        kind, cur = line[0], bytearray(line[1:])
        for i in range(stride):
            left = cur[i - 4] if i >= 4 else 0
            up = prev[i]
            upleft = prev[i - 4] if i >= 4 else 0
            if kind == 1:
                cur[i] = (cur[i] + left) & 255
            elif kind == 2:
                cur[i] = (cur[i] + up) & 255
            elif kind == 3:
                cur[i] = (cur[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                pred = left if pa <= pb and pa <= pc else up if pb <= pc else upleft
                cur[i] = (cur[i] + pred) & 255
        prev = bytes(cur)
        # A transparent pixel prints as white paper.
        rows.append([cur[x * 4] < 128 and cur[x * 4 + 3] >= 128 for x in range(width)])
    return rows


class Page:
    def __init__(self):
        self.ops = []

    def rect(self, x_mm, y_mm, w_mm, h_mm, grey=0.0):
        """Filled rectangle; origin top-left of the page, y down, in mm."""
        x, w, h = x_mm * MM, w_mm * MM, h_mm * MM
        y = PAGE_H - y_mm * MM - h
        self.ops.append(f"{grey:.2f} g {x:.3f} {y:.3f} {w:.3f} {h:.3f} re f")

    def line(self, x1, y1, x2, y2, width_pt=0.4, grey=0.5):
        self.ops.append(
            f"{grey:.2f} G {width_pt} w {x1 * MM:.3f} {PAGE_H - y1 * MM:.3f} m "
            f"{x2 * MM:.3f} {PAGE_H - y2 * MM:.3f} l S")

    def circle(self, cx, cy, r, width_pt=0.4, grey=0.5):
        k = 0.5523 * r
        pts = [(cx + r, cy), (cx + r, cy + k, cx + k, cy + r, cx, cy + r),
               (cx - k, cy + r, cx - r, cy + k, cx - r, cy),
               (cx - r, cy - k, cx - k, cy - r, cx, cy - r),
               (cx + k, cy - r, cx + r, cy - k, cx + r, cy)]
        out = [f"{grey:.2f} G {width_pt} w {pts[0][0] * MM:.3f} {PAGE_H - pts[0][1] * MM:.3f} m"]
        for c in pts[1:]:
            xs = [f"{c[i] * MM:.3f} {PAGE_H - c[i + 1] * MM:.3f}" for i in (0, 2, 4)]
            out.append(" ".join(xs) + " c")
        self.ops.append(" ".join(out) + " S")

    def text(self, x_mm, y_mm, s, size=9):
        s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        self.ops.append(f"0 g BT /F1 {size} Tf {x_mm * MM:.3f} {PAGE_H - y_mm * MM:.3f} Td ({s}) Tj ET")

    def tag(self, cells, x_mm, y_mm, printed_mm):
        """Draw a tag with its top-left corner at (x, y), printed_mm wide."""
        n = len(cells)
        cell = printed_mm / n
        self.rect(x_mm, y_mm, printed_mm, printed_mm, grey=1.0)
        for r, row in enumerate(cells):
            c = 0
            while c < n:  # merge runs so no hairline gaps appear between cells
                if row[c]:
                    start = c
                    while c < n and row[c]:
                        c += 1
                    self.rect(x_mm + start * cell, y_mm + r * cell, (c - start) * cell, cell + 0.02)
                else:
                    c += 1

    def carrier(self, cx, cy, side):
        """Cut square with centre ticks, for lining the tag up on the bar axis."""
        h = side / 2
        for x1, y1, x2, y2 in [(cx - h, cy - h, cx + h, cy - h), (cx + h, cy - h, cx + h, cy + h),
                               (cx + h, cy + h, cx - h, cy + h), (cx - h, cy + h, cx - h, cy - h)]:
            self.line(x1, y1, x2, y2)
        for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            self.line(cx + dx * (h - 2.5), cy + dy * (h - 2.5), cx + dx * (h + 4), cy + dy * (h + 4), 0.6, 0.0)

    def ruler(self, x_mm, y_mm, length=100):
        self.line(x_mm, y_mm, x_mm + length, y_mm, 0.6, 0.0)
        for i in range(0, length + 1, 10):
            self.line(x_mm + i, y_mm - (3 if i % 50 == 0 else 1.5), x_mm + i, y_mm, 0.6, 0.0)
        self.text(x_mm, y_mm + 4.5, f"Scale check: this line is {length} mm, and the box below is the size "
                                    "of a credit card (85.60 x 53.98 mm).", 8)
        self.text(x_mm, y_mm + 8.5, "Lay a card on the box. If its edges do not land on the lines, "
                                    "reprint at 100% with fit-to-page off.", 8)
        # ISO/IEC 7810 ID-1: every credit, debit and ID card is this size.
        w, h, top = 85.60, 53.98, y_mm + 12
        left = x_mm + (length - w) / 2
        for x1, y1, x2, y2 in [(left, top, left + w, top), (left + w, top, left + w, top + h),
                               (left + w, top + h, left, top + h), (left, top + h, left, top)]:
            self.line(x1, y1, x2, y2, 0.5, 0.0)


def big_tag_page(cells, family, tag_id, edge_cells, edge_where):
    printed, side = 90.0, 100.0
    cx, cy = 215.9 / 2, 110.0
    page = Page()
    page.text(20, 18, f"{family}  ID {tag_id}  -  {printed:.0f} mm printed, on a {side:.0f} mm carrier", 12)
    edge = printed * edge_cells / len(cells)
    page.text(20, 25, f"Nominal detection edge (tagsize): {edge:.0f} mm, {edge_where}. "
                      "Measure yours with calipers.", 9)
    page.text(20, 31, "Cut on the grey square. The black ticks mark the carrier's centre lines; "
                      "keep the white margin clean.", 9)
    page.carrier(cx, cy, side)
    page.tag(cells, cx - printed / 2, cy - printed / 2, printed)
    page.ruler(cx - 50, 185)
    page.text(20, 262, "hpc-vbt-live, probes/bar-end-tag. Tag pattern from AprilRobotics/apriltag-imgs (BSD-2-Clause).", 7)
    return page


def fallback_page(cells36):
    page = Page()
    page.text(20, 18, "Fallback: tag36h11 ID 0 at 35 mm printed (28 mm detection edge)", 12)
    page.text(20, 25, "Stays inside a 50 mm sleeve end. Cut on the grey circle; two copies.", 9)
    for cx in (65.0, 150.0):
        page.circle(cx, 70, 25)
        page.tag(cells36, cx - 17.5, 70 - 17.5, 35.0)
    page.ruler(215.9 / 2 - 50, 125)
    page.text(20, 262, "hpc-vbt-live, probes/bar-end-tag. Tag pattern from AprilRobotics/apriltag-imgs (BSD-2-Clause).", 7)
    return page


def write_pdf(pages, path):
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", None,
               b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    kids = []
    for page in pages:
        stream = "\n".join(page.ops).encode("ascii")
        objects.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
        content = len(objects)
        objects.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents %d 0 R "
                       b"/Resources << /Font << /F1 3 0 R >> >> >>" % (PAGE_W, PAGE_H, content))
        kids.append(len(objects))
    objects[1] = ("<< /Type /Pages /Count %d /Kids [%s] >>" % (
        len(kids), " ".join(f"{k} 0 R" for k in kids))).encode()
    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for i, obj in enumerate(objects, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + obj + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    path.write_bytes(out)


def main():
    t36 = read_cells(HERE / "tags" / "tag36_11_00000.png")
    t41 = read_cells(HERE / "tags" / "tag41_12_00000.png")
    assert len(t36) == 10 and len(t41) == 9
    for name, cells in (("tag36h11", t36), ("tagStandard41h12", t41)):
        print(name)
        for row in cells:
            print("  " + "".join("#" if c else "." for c in row))
    pages = [big_tag_page(t36, "tag36h11", 0, 8, "the outer edge of the black square"),
             big_tag_page(t41, "tagStandard41h12", 0, 5, "the inner edge of the black ring"),
             fallback_page(t36)]
    out = HERE / "bar-end-tags.pdf"
    write_pdf(pages, out)
    print(f"wrote {out.name}: {len(pages)} pages")


if __name__ == "__main__":
    sys.exit(main())
