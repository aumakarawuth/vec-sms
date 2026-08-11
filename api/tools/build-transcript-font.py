# -*- coding: utf-8 -*-
"""
ย่อชุดอักขระของ TH Sarabun New แล้วสร้างไฟล์ฟอนต์ฝังในหน้าพิมพ์ใบ รบ.

═══ ทำไมต้องฝังฟอนต์ ไม่ใช่พึ่งฟอนต์ในเครื่อง ═══
เรขาคณิตของใบ รบ. ทั้งใบคิดบนความกว้างตัวอักษรของ THSarabunNew (0.361 em
ต่ออักขระไทย วัดจากไฟล์ฟอนต์จริง) เครื่องที่ไม่มีฟอนต์นี้จะตกไปใช้ตัวสำรอง
ซึ่งกว้างกว่า 7% (Angsana) ถึง 45% (Leelawadee UI) แล้วชื่อวิชาจะตัดบรรทัด
คนละที่กับใบจริง — เอกสารราชการไม่ควรหน้าตาต่างกันตามว่าเครื่องไหนลงอะไรไว้

═══ ทำไมย่อชุดอักขระ ═══
ไฟล์เต็มเป็น base64 แล้วหนัก ~430 KB ต่อหน้าที่พิมพ์ (Regular + Bold)
ซึ่งติดไปกับ**ทุกคำขอพิมพ์** ย่อเหลือเฉพาะอักขระไทยกับละตินที่ใบใช้จริง
แล้วบีบเป็น woff2 ได้ราวหนึ่งในห้า

═══ วิธีรันใหม่ ═══
    python api/tools/build-transcript-font.py
ต้องมี fonttools + brotli (pip install fonttools brotli) และไฟล์ฟอนต์ต้นทาง
ในเครื่อง — ผลลัพธ์คือ api/src/modules/documents/fonts.ts ซึ่ง commit ลง repo
จึงไม่ต้องรันซ้ำเว้นแต่จะเปลี่ยนชุดอักขระหรือเปลี่ยนรุ่นฟอนต์

═══ สัญญาอนุญาต ═══
TH Sarabun New เป็นหนึ่งใน 13 ฟอนต์แห่งชาติที่เผยแพร่ให้ใช้ ทำซ้ำ และ
แจกจ่ายได้โดยไม่มีค่าใช้จ่าย การฝังมากับหน้าพิมพ์แบบฟอร์มของ สอศ.
อยู่ในขอบเขตการใช้งานที่ตั้งใจไว้
"""
import base64
import io
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

# ─── ชุดอักขระที่ใบ รบ. ใช้จริง ────────────────────────────────────
# ไทยทั้งบล็อก (รวมเลขไทย ๐-๙ และ ฯลฯ) + ละตินพื้นฐาน + เครื่องหมายที่แม่แบบใช้
UNICODES = (
    list(range(0x0020, 0x007F))          # ละตินพื้นฐาน + ตัวเลข + เครื่องหมาย
    + list(range(0x0E00, 0x0E80))        # ไทยทั้งบล็อก
    + [
        0x00A0,  # เว้นวรรคไม่ตัดบรรทัด (&nbsp; ในช่องลงนาม)
        0x00B7,  # ·
        0x00D7,  # ×  ใช้ใน "2.5 × 3 ซม." และหัวคอลัมน์ (1)×(2)
        0x2013, 0x2014,          # – —
        0x2018, 0x2019, 0x201C, 0x201D,
        0x2022,  # •
        0x2026,  # …
    ]
)

FONT_DIR = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Windows", "Fonts"
)
SOURCES = [
    ("regular", "400", "THSarabunNew.ttf"),
    ("bold", "700", "THSarabunNew Bold.ttf"),
]
OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "src", "modules", "documents", "fonts.ts",
)


def subset_to_woff2(path: str) -> bytes:
    font = TTFont(path)
    opts = subset.Options()
    opts.layout_features = ["*"]      # ไทยต้องใช้ mark/mkmk จัดสระและวรรณยุกต์
    opts.name_IDs = [1, 2, 3, 4, 6]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(font)
    font.flavor = "woff2"
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


def main() -> int:
    parts, report = [], []
    for key, weight, filename in SOURCES:
        src = os.path.join(FONT_DIR, filename)
        if not os.path.exists(src):
            print(f"ไม่พบไฟล์ฟอนต์: {src}", file=sys.stderr)
            return 1
        data = subset_to_woff2(src)
        b64 = base64.b64encode(data).decode("ascii")
        parts.append((key, weight, b64, len(data), os.path.getsize(src)))
        report.append(
            f"  {filename}: {os.path.getsize(src)//1024} KB "
            f"→ woff2 {len(data)//1024} KB → base64 {len(b64)//1024} KB"
        )

    lines = [
        "/**",
        " * ฟอนต์ TH Sarabun New ที่ย่อชุดอักขระแล้ว สำหรับฝังในหน้าพิมพ์ใบ รบ.",
        " *",
        " * ═══ ไฟล์นี้สร้างด้วยเครื่องมือ ห้ามแก้ด้วยมือ ═══",
        " * สร้างใหม่ด้วย `python api/tools/build-transcript-font.py`",
        " * (เหตุผลว่าทำไมต้องฝังฟอนต์ และย่อชุดอักขระอย่างไร อยู่ในไฟล์นั้น)",
        " *",
        " * ═══ ทำไมเก็บเป็น .ts ไม่ใช่ .woff2 ข้าง ๆ ═══",
        " * ชั้น API คอมไพล์ด้วย `tsc` อย่างเดียว ซึ่ง**ไม่คัดลอกไฟล์ที่ไม่ใช่ .ts**",
        " * ไปที่ dist/ ถ้าเก็บเป็นไฟล์ฟอนต์ หน้าพิมพ์บนระบบจริงจะไม่มีฟอนต์ติดไป",
        " * ด้วยโดยที่เทสต์บนเครื่องพัฒนายังผ่าน — เป็นรูปเดียวกับของที่ประกาศ",
        " * เจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น",
        " *",
        " * ═══ สัญญาอนุญาต ═══",
        " * TH Sarabun New เป็นหนึ่งใน 13 ฟอนต์แห่งชาติที่เผยแพร่ให้ใช้ ทำซ้ำ",
        " * และแจกจ่ายได้โดยไม่มีค่าใช้จ่าย",
        " */",
        "",
        "/** woff2 ที่ย่อชุดอักขระแล้ว เข้ารหัส base64 (ไทยทั้งบล็อก + ละตินพื้นฐาน) */",
    ]
    for key, weight, b64, raw, orig in parts:
        lines.append(f"const {key.upper()} =")
        for i in range(0, len(b64), 100):
            end = ";" if i + 100 >= len(b64) else ""
            lines.append(f"  '{b64[i:i + 100]}'{'' if end else ' +'}{end}")
        lines.append("")

    lines += [
        "/**",
        " * `@font-face` ที่แม่แบบใบ รบ. ทุกตัวแทรกไว้ต้น CSS",
        " *",
        " * ใช้ data: URI เพราะหน้าพิมพ์**ห้ามอ้างไฟล์ภายนอกเลย** — เจ้าหน้าที่",
        " * ต้องพิมพ์ใบได้แม้อินเทอร์เน็ตของวิทยาลัยล่ม และ API-156 ตรวจข้อนี้อยู่",
        " */",
        "export const TRANSCRIPT_FONT_FACE = `",
        "  @font-face {",
        "    font-family: 'TH Sarabun New';",
        "    font-weight: 400; font-style: normal; font-display: block;",
        "    src: url(data:font/woff2;base64,${REGULAR}) format('woff2');",
        "  }",
        "  @font-face {",
        "    font-family: 'TH Sarabun New';",
        "    font-weight: 700; font-style: normal; font-display: block;",
        "    src: url(data:font/woff2;base64,${BOLD}) format('woff2');",
        "  }`;",
        "",
    ]
    with open(os.path.abspath(OUT), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))

    print("สร้าง fonts.ts แล้ว")
    print("\n".join(report))
    total = sum(len(b64) for _, _, b64, _, _ in parts)
    print(f"  รวม base64 ที่ติดไปกับทุกหน้าที่พิมพ์: {total // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
