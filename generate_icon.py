"""Generate crisp multi-size POS icon for Lamsa.
Small sizes: bold simple design. Large sizes: detailed receipt."""
from PIL import Image, ImageDraw, ImageFont
import os

FONT_PATH = r"C:\Users\Mageed\Desktop\FlutterProject\Lamsa-main\assets\fonts\Cairo-Variable.ttf"
OUT_DIR = r"C:\Users\Mageed\Desktop\FlutterProject\Lamsa-main"

# ── Colours ──────────────────────────────────────────────
BG     = (15, 23, 42)
CARD   = (255, 255, 255)
ACCENT = (99, 102, 241)
GREY   = (203, 213, 225)
DARK   = (30, 41, 59)


def draw_simple_icon(size):
    """Bold simple icon for small sizes (16-64): just 'L' on colored bg."""
    # Supersample 8x
    S = size * 8
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Background
    d.rounded_rectangle([0, 0, S-1, S-1], radius=S//4, fill=BG)

    # Accent circle
    cx, cy = S//2, S*48//100
    cr = S*34//100
    d.ellipse([cx-cr, cy-cr, cx+cr, cy+cr], fill=ACCENT)

    # Letter L
    try:
        font = ImageFont.truetype(FONT_PATH, size=int(cr * 1.6))
    except:
        font = ImageFont.load_default()
    bb = d.textbbox((0, 0), "L", font=font)
    tw, th = bb[2]-bb[0], bb[3]-bb[1]
    d.text((cx - tw//2 - bb[0], cy - th//2 - bb[1]), "L", fill=CARD, font=font)

    return img.resize((size, size), Image.LANCZOS)


def draw_detailed_icon(size):
    """Detailed receipt icon for large sizes (128+)."""
    # Supersample 4x
    S = size * 4
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Background with subtle gradient
    d.rounded_rectangle([0, 0, S-1, S-1], radius=S//4, fill=BG)
    # Lighter top band
    for y in range(S//6, S//3):
        alpha = int(15 * (1 - abs(y - S//4) / (S//12)))
        if alpha > 0:
            overlay = Image.new('RGBA', (S, 1), (255, 255, 255, alpha))
            img.paste(Image.alpha_composite(
                img.crop((0, y, S, y+1)), overlay), (0, y))
    d = ImageDraw.Draw(img)

    # Receipt card
    mx = S * 20 // 100
    ry1, ry2 = S * 8 // 100, S * 78 // 100
    d.rounded_rectangle([mx, ry1, S-mx, ry2], radius=S//22, fill=CARD)

    # Torn bottom
    tw_cnt = 12
    tw_w = (S - 2*mx) // tw_cnt
    for i in range(tw_cnt):
        x = mx + i * tw_w
        d.polygon([(x, ry2), (x + tw_w//2, ry2 + S//32), (x + tw_w, ry2)], fill=CARD)

    # --- Receipt content ---
    pad = S * 5 // 100
    lx1, lx2 = mx + pad, S - mx - pad
    lh = max(S // 70, 4)
    gap = S * 55 // 1000
    y = ry1 + S * 7 // 100

    # Header
    d.rounded_rectangle([lx1, y, lx1 + (lx2-lx1)*55//100, y + lh + 4], radius=lh, fill=ACCENT)
    y += int(gap * 1.5)

    # Items
    for wl, wr in [(0.50, 0.18), (0.40, 0.22), (0.55, 0.15), (0.35, 0.20)]:
        d.rounded_rectangle([lx1, y, lx1+int((lx2-lx1)*wl), y+lh], radius=lh//2, fill=GREY)
        d.rounded_rectangle([lx2-int((lx2-lx1)*wr), y, lx2, y+lh], radius=lh//2, fill=GREY)
        y += gap

    # Separator
    sy = y + gap//4
    for sx in range(lx1, lx2, S//60):
        d.rectangle([sx, sy, min(sx + S//100, lx2), sy+2], fill=GREY)
    y = sy + gap

    # Total
    tl = lh + 6
    d.rounded_rectangle([lx1, y, lx1+(lx2-lx1)*30//100, y+tl], radius=tl//2, fill=DARK)
    d.rounded_rectangle([lx2-(lx2-lx1)*22//100, y, lx2, y+tl], radius=tl//2, fill=ACCENT)
    y += int(gap * 1.8)

    # Barcode
    bh = S // 16
    bw_total = (lx2 - lx1) * 60 // 100
    bx = (lx1 + lx2) // 2 - bw_total // 2
    import random
    random.seed(42)
    x = bx
    while x < bx + bw_total:
        w = random.choice([3, 5, 7, 4, 6]) * S // 1024
        w = max(w, 2)
        if random.random() > 0.3:
            d.rectangle([x, y, x+w-1, y+bh], fill=DARK)
        x += w + max(1, S//600)

    # Badge
    br = S * 12 // 100
    bcx = S - mx - br//3
    bcy = S - S * 14 // 100

    # Shadow
    d.ellipse([bcx-br-4, bcy-br+6, bcx+br+4, bcy+br+14], fill=(0,0,0,40))
    # Circle
    d.ellipse([bcx-br, bcy-br, bcx+br, bcy+br], fill=ACCENT)
    d.ellipse([bcx-br, bcy-br, bcx+br, bcy+br], outline=CARD, width=max(4, S//200))

    # "L"
    try:
        font = ImageFont.truetype(FONT_PATH, size=int(br * 1.4))
    except:
        font = ImageFont.load_default()
    bb = d.textbbox((0, 0), "L", font=font)
    tw, th = bb[2]-bb[0], bb[3]-bb[1]
    d.text((bcx-tw//2-bb[0], bcy-th//2-bb[1]-2), "L", fill=CARD, font=font)

    return img.resize((size, size), Image.LANCZOS)


# ── Generate all sizes ───────────────────────────────────
SIMPLE_SIZES = [16, 24, 32, 48, 64]
DETAIL_SIZES = [128, 256, 512]

print("Generating icons...")
icons = {}
for s in SIMPLE_SIZES:
    icons[s] = draw_simple_icon(s)
    print(f"  {s}x{s} (simple)")

for s in DETAIL_SIZES:
    icons[s] = draw_detailed_icon(s)
    print(f"  {s}x{s} (detailed)")

# Save large PNG
png_path = os.path.join(OUT_DIR, "assets", "app_icon.png")
icons[512].save(png_path, "PNG")
print(f"PNG saved: {png_path}")

# Save ICO
all_sizes = sorted(icons.keys())
ico_imgs = [icons[s] for s in all_sizes]
ico_path = os.path.join(OUT_DIR, "windows", "runner", "resources", "app_icon.ico")
ico_imgs[0].save(
    ico_path, format='ICO',
    sizes=[(s, s) for s in all_sizes],
    append_images=ico_imgs[1:]
)
print(f"ICO saved: {ico_path}")
print("Done!")
