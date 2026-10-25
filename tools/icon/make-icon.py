# Ícone do GoatRemote e logótipos da cabra (goat-mask.png: branco = cabra; desenho feito à parte).
#   python3 tools/icon/make-icon.py tools/icon/goat-mask.png <pasta de saída>   (precisa do Pillow)
import sys, math
from PIL import Image, ImageDraw, ImageFilter
mask_path, out = sys.argv[1], sys.argv[2]
sky, violet = (56, 189, 248), (139, 92, 246)
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def gradient(S):
    g = Image.new("RGB", (64, 64))
    p = g.load()
    for y in range(64):
        for x in range(64):
            p[x, y] = lerp(sky, violet, (x + y) / 126)
    return g.resize((S, S), Image.BILINEAR)
goat = Image.open(mask_path).convert("L")

# Logótipos: 1024 transparentes, com gradiente e em branco.
for name, fill in (("goat-gradient", None), ("goat-white", (255, 255, 255)), ("goat-navy", (3, 32, 89))):
    m = goat.resize((1024, 1024), Image.LANCZOS)
    rgb = gradient(1024) if fill is None else Image.new("RGB", (1024, 1024), fill)
    img = rgb.convert("RGBA")
    img.putalpha(m)
    img.save(f"{out}/{name}.png")

def icon(arrows, goat_size, dx=0.0, dy=0.0):
    S = 4096
    u = S / 100
    cx = cy = S / 2
    bg = Image.new("RGB", (S, S), (10, 13, 22))
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.35, S * 0.9, S * 0.75), fill=(30, 46, 90))
    bg = Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(S * 0.12)), 0.6)
    grad = gradient(S)
    R, w = 33 * u, 5.5 * u
    ring = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring).ellipse((cx - R, cy - R, cx + R, cy + R), outline=255, width=int(w))
    img = bg.copy()
    img.paste(grad, (0, 0), ring)
    side = int(goat_size * u)
    m = goat.resize((side, side), Image.LANCZOS)
    layer = Image.new("L", (S, S), 0)
    layer.paste(m, (int(cx - side / 2 + dx * u), int(cy - side / 2 + dy * u)))
    img.paste(grad, (0, 0), layer)
    if arrows:
        a_mask = Image.new("L", (S, S), 0)
        ad = ImageDraw.Draw(a_mask)
        d, a, lw = 25.2 * u, 3.0 * u, int(1.9 * u)
        for ang in (0, 90, 180, 270):
            t = math.radians(ang)
            ux, uy = math.cos(t), -math.sin(t)
            px, py = -uy, ux
            tip = (cx + ux * (d + a * 0.5), cy + uy * (d + a * 0.5))
            l = (cx + ux * (d - a * 0.5) + px * a, cy + uy * (d - a * 0.5) + py * a)
            r = (cx + ux * (d - a * 0.5) - px * a, cy + uy * (d - a * 0.5) - py * a)
            ad.line([l, tip, r], fill=255, width=lw, joint="curve")
            for p in (l, tip, r):
                ad.ellipse((p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2), fill=255)
        img.paste((255, 255, 255), (0, 0), a_mask)
    return img.resize((1024, 1024), Image.LANCZOS)

icon(True, 40, dx=0.5).save(f"{out}/icon-arrows.png")
icon(False, 50, dx=0.5).save(f"{out}/icon-ring.png")
print("ok")
