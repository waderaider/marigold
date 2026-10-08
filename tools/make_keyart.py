#!/usr/bin/env python3
"""MARIGOLD v0.5.0 key-art generator.

Builds a consistent set of folk-styled chapter/experience preview cards
(512x320 PNG) for the 2D menu: plum/marigold identity, papel-picado trim,
per-chapter silhouette motif, title text. All art is original geometry drawn
in code - no copyrighted or third-party imagery.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "keyart")
W, H = 512, 320

MARIGOLD = (255, 166, 40)
MARIGOLD_DEEP = (214, 110, 10)
PINK = (255, 92, 138)
CREAM = (255, 236, 205)
PLUM_TOP = (46, 14, 38)
PLUM_BOT = (16, 5, 22)
TEAL = (64, 200, 220)


def font(sz):
    try:
        return ImageFont.load_default(size=sz)
    except TypeError:
        return ImageFont.load_default()


def vgrad(d):
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(PLUM_TOP[i] + (PLUM_BOT[i] - PLUM_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)


def papel_trim(d):
    """Scalloped papel-picado strip along the top edge."""
    d.rectangle([0, 0, W, 34], fill=(24, 8, 26))
    for x in range(0, W, 42):
        d.pieslice([x + 4, -14, x + 38, 30], 0, 180, fill=(0, 0, 0, 0))
    cols = [MARIGOLD, PINK, TEAL, (150, 110, 255)]
    for i, x in enumerate(range(0, W, 42)):
        d.arc([x + 4, -14, x + 38, 30], 0, 180, fill=cols[i % 4], width=3)
    d.line([(0, 36), (W, 36)], fill=MARIGOLD_DEEP, width=2)


def glow_dot(d, x, y, r, col, layers=4):
    for i in range(layers, 0, -1):
        a = int(46 * (1 - i / (layers + 1)))
        d.ellipse([x - r * i, y - r * i, x + r * i, y + r * i],
                  fill=col + (a,))


def title_block(d, title, sub):
    d.rectangle([0, H - 74, W, H], fill=(10, 3, 12))
    d.line([(0, H - 74), (W, H - 74)], fill=MARIGOLD_DEEP, width=2)
    f1, f2 = font(40), font(26)
    d.text((24, H - 66), title, font=f1, fill=CREAM)
    d.text((24, H - 30), sub, font=f2, fill=(255, 200, 120))


def marigold_dot(d, x, y, r=7):
    d.ellipse([x - r, y - r, x + r, y + r], fill=MARIGOLD)
    d.ellipse([x - r * 0.55, y - r * 0.55, x + r * 0.55, y + r * 0.55],
              fill=MARIGOLD_DEEP)


# ---------------- motifs ----------------

def motif_ofrenda(d):
    cx, cy, R = 256, 215, 100
    d.arc([cx - R, cy - R, cx + R, cy + R], 180, 360, fill=(120, 60, 20), width=7)
    for a in range(0, 181, 14):
        x = cx + R * math.cos(math.radians(180 - a))
        y = cy - R * math.sin(math.radians(180 - a))
        marigold_dot(d, x, y, 8)
    for i, fx in enumerate([186, 256, 326]):
        glow_dot(d, fx, 170, 15, MARIGOLD)
        d.ellipse([fx - 5, 158, fx + 5, 170], fill=(255, 240, 200))
        d.rectangle([fx - 24, 176, fx + 24, 232], outline=CREAM, width=3)
        d.ellipse([fx - 9, 192, fx + 9, 210], fill=(255, 200, 120))


def motif_bridge(d):
    d.ellipse([356, 40, 452, 136], fill=(235, 225, 200))          # moon
    d.ellipse([366, 50, 442, 126], fill=(200, 170, 120))
    for y in range(190, 300, 8):                                    # water
        w = 200 + 40 * math.sin(y * 0.3)
        d.line([(256 - w, y), (256 + w, y)], fill=(20, 40, 90))
    d.line([(256 - 60, 200), (256 + 60, 200)], fill=(240, 200, 120), width=5)
    d.arc([96, 60, 416, 340], 200, 340, fill=MARIGOLD, width=14)   # bridge arc
    for a in range(205, 336, 13):
        x = 256 + 160 * math.cos(math.radians(a))
        y = 200 + 140 * math.sin(math.radians(a))
        marigold_dot(d, x, y, 8)


def motif_alebrije(d):
    bx, by = 256, 200
    d.ellipse([bx - 90, by - 45, bx + 90, by + 45], fill=PINK)     # body
    d.ellipse([bx + 55, by - 95, bx + 125, by - 25], fill=PINK)    # head
    d.polygon([(bx + 80, by - 90), (bx + 60, by - 140), (bx + 100, by - 100)],
              fill=MARIGOLD)                                       # horn
    d.polygon([(bx + 105, by - 85), (bx + 105, by - 135), (bx + 125, by - 90)],
              fill=TEAL)
    d.ellipse([bx + 88, by - 70, bx + 100, by - 58], fill=(20, 8, 16))  # eye
    d.ellipse([bx + 91, by - 67, bx + 97, by - 61], fill=MARIGOLD)
    for wx, wy, c in [(-40, -70, TEAL), (10, -85, (150, 110, 255))]:  # wings
        d.polygon([(bx + wx, by + wy), (bx + wx - 70, by + wy - 60),
                   (bx + wx - 20, by + wy + 10)], fill=c)
    for lx in [-50, -10, 30]:                                      # legs
        d.rectangle([bx + lx - 9, by + 30, bx + lx + 9, by + 95], fill=PINK)
    d.polygon([(bx - 90, by), (bx - 150, by - 50), (bx - 130, by + 10)],
              fill=MARIGOLD)                                       # tail
    for i in range(6):                                             # spots
        sx = bx - 60 + (i % 3) * 45
        sy = by - 20 + (i // 3) * 35
        d.ellipse([sx - 9, sy - 9, sx + 9, sy + 9], fill=TEAL)


def motif_papel(d):
    cols = [PINK, MARIGOLD, TEAL, (150, 110, 255), (120, 220, 120)]
    for row, y0 in enumerate([60, 140]):
        for i in range(5):
            x0 = 36 + i * 92
            c = cols[(i + row) % len(cols)]
            d.rectangle([x0, y0, x0 + 76, y0 + 56], fill=c)
            for dx in range(12, 70, 16):
                d.ellipse([x0 + dx - 6, y0 + 20, x0 + dx + 6, y0 + 34],
                          fill=(16, 5, 22))
            for ex in [x0 + 8, x0 + 68]:
                d.pieslice([ex - 12, y0 + 44, ex + 12, y0 + 68], 180, 360,
                           fill=(16, 5, 22))
        d.line([(0, y0 - 8), (W, y0 - 8)], fill=(90, 50, 30), width=4)


def motif_baile(d):
    cx, cy = 256, 190
    for dx, s, c in [(-120, 0.8, PINK), (120, 0.8, TEAL), (0, 1.0, MARIGOLD)]:
        x = cx + dx
        d.ellipse([x - 22 * s, cy - 105 * s, x + 22 * s, cy - 61 * s],
                  fill=(240, 225, 195))                            # skull
        d.ellipse([x - 10 * s, cy - 92 * s, x - 2 * s, cy - 80 * s],
                  fill=(20, 8, 16))
        d.ellipse([x + 2 * s, cy - 92 * s, x + 10 * s, cy - 80 * s],
                  fill=(20, 8, 16))
        d.ellipse([x - 7 * s, cy - 88 * s, x - 4 * s, cy - 84 * s], fill=c)
        d.ellipse([x + 4 * s, cy - 88 * s, x + 7 * s, cy - 84 * s], fill=c)
        d.rectangle([x - 16 * s, cy - 58 * s, x + 16 * s, cy + 10 * s],
                    fill=(240, 225, 195))                          # ribs
        for ry in range(-50, 8, 14):
            d.line([(x - 20 * s, cy + ry * s), (x + 20 * s, cy + ry * s)],
                   fill=(120, 90, 70), width=3)
        d.line([(x - 30 * s, cy - 40 * s), (x - 70 * s, cy - 95 * s)],
               fill=(240, 225, 195), width=int(13 * s))             # arms up
        d.line([(x + 30 * s, cy - 40 * s), (x + 70 * s, cy - 95 * s)],
               fill=(240, 225, 195), width=int(13 * s))
    for px in range(40, W, 60):
        marigold_dot(d, px, 285, 9)


def motif_guitarra(d):
    bx, by = 220, 190
    d.ellipse([bx - 75, by - 25, bx + 5, by + 75], fill=(150, 84, 32))   # lower bout
    d.ellipse([bx - 15, by - 85, bx + 55, by - 5], fill=(150, 84, 32))  # upper bout
    d.ellipse([bx - 60, by - 10, bx - 10, by + 60], fill=(40, 14, 8))   # soundhole
    d.ellipse([bx - 48, by + 2, bx - 22, by + 48], fill=(10, 4, 4))
    for sx in range(-2, 3):
        d.line([(bx - 40 + sx * 12, by - 80), (bx - 90 + sx * 12, by - 170)],
               fill=(220, 190, 140), width=2)
    d.polygon([(bx - 10, by - 70), (bx - 70, by - 160), (bx - 30, by - 175),
               (bx + 30, by - 85)], fill=(110, 60, 22))                # neck
    d.ellipse([bx - 95, by - 195, bx - 45, by - 145], fill=(90, 48, 18))  # headstock
    for i in range(6):
        y = by - 60 + i * 14
        d.line([(bx - 62, y), (bx - 2, y)], fill=(235, 215, 170), width=2)  # strings
    for i, (nx, ny) in enumerate([(400, 120), (440, 170), (380, 210)]):
        glow_dot(d, nx, ny, 14, MARIGOLD)
        d.ellipse([nx - 8, ny - 8, nx + 8, ny + 8], fill=MARIGOLD)   # falling notes


def motif_mano(d):
    cx, cy = 256, 185
    d.rounded_rectangle([cx - 55, cy - 30, cx + 55, cy + 80], 30,
                        fill=(255, 214, 170))                          # palm
    for i, fx in enumerate([-42, -14, 14, 42]):
        d.rounded_rectangle([cx + fx - 13, cy - 105, cx + fx + 13, cy - 25], 13,
                            fill=(255, 214, 170))                      # fingers
    d.rounded_rectangle([cx + 55, cy - 10, cx + 105, cy + 25], 15,
                        fill=(255, 214, 170),)                         # thumb
    glow_dot(d, cx - 14, cy - 120, 18, MARIGOLD)                       # pinch spark
    glow_dot(d, cx + 14, cy - 120, 18, PINK)
    marigold_dot(d, cx - 14, cy - 120, 10)
    for sx, sy in [(120, 90), (400, 100), (150, 260), (380, 250)]:
        glow_dot(d, sx, sy, 12, TEAL)


def motif_espejo(d):
    cx, cy = 256, 175
    d.rounded_rectangle([cx - 110, cy - 115, cx + 110, cy + 115], 26,
                        fill=(70, 40, 60))                             # frame
    d.rounded_rectangle([cx - 96, cy - 101, cx + 96, cy + 101], 18,
                        fill=(30, 60, 80))                             # mirror
    for i in range(8):
        a = i / 8 * 2 * math.pi
        gx = cx + 110 * math.cos(a)
        gy = cy + 115 * math.sin(a)
        marigold_dot(d, gx, gy, 8)
    x = cx
    d.ellipse([x - 20, cy - 95, x + 20, cy - 55], fill=(240, 225, 195))  # skull
    d.ellipse([x - 9, cy - 82, x - 2, cy - 72], fill=(20, 8, 16))
    d.ellipse([x + 2, cy - 82, x + 9, cy - 72], fill=(20, 8, 16))
    d.rectangle([x - 15, cy - 52, x + 15, cy + 15], fill=(240, 225, 195))
    d.line([(x - 28, cy - 35), (x - 62, cy - 80)], fill=(240, 225, 195),
           width=12)
    d.line([(x + 28, cy - 35), (x + 62, cy - 80)], fill=(240, 225, 195),
           width=12)
    d.line([(x - 10, cy + 15), (x - 16, cy + 95)], fill=(240, 225, 195),
           width=13)
    d.line([(x + 10, cy + 15), (x + 16, cy + 95)], fill=(240, 225, 195),
           width=13)
    d.line([(120, 60), (392, 60)], fill=(255, 255, 255, 60), width=10)  # sheen


CARDS = [
    ("ch1_ofrenda", "The Ofrenda", "Build the offering", motif_ofrenda),
    ("ch2_bridge", "The Marigold Bridge", "Cross the glowing bridge", motif_bridge),
    ("ch3_alebrijes", "Plaza de los Alebrijes", "Meet the spirit guides", motif_alebrije),
    ("ch4_papel", "Papel Picado Canopy", "Dance under cut paper", motif_papel),
    ("ch5_baile", "El Gran Baile", "The grand dance finale", motif_baile),
    ("guitarra", "Guitarra Mexicana", "Rhythm-strum folk guitar", motif_guitarra),
    ("mano_magica", "Mano Magica", "A hand-tracking tour", motif_mano),
    ("espejo", "Gran Baile: Espejo", "Mirror dance, body tracked", motif_espejo),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, title, sub, motif in CARDS:
        img = Image.new("RGBA", (W, H), (16, 5, 22, 255))
        d = ImageDraw.Draw(img, "RGBA")
        vgrad(d)
        motif(d)
        papel_trim(d)
        title_block(d, title, sub)
        path = os.path.join(OUT, key + ".png")
        img.convert("RGB").save(path, "PNG")
        print("wrote", path)


if __name__ == "__main__":
    main()
