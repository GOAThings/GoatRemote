# O ícone da app (1024×1024): python3 tools/icon/make-icon.py ios/GoatRemote/Assets.xcassets/AppIcon.appiconset/icon-1024.png
# Precisa do Pillow. Anel e setas do comando com a cabeça da cabra GOAT ao centro.
import sys, math
from PIL import Image, ImageDraw, ImageFilter
S = 4096
u = S / 100.0
out = sys.argv[1]
cx, cy = S / 2, S / 2
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
sky, violet = (56, 189, 248), (139, 92, 246)
def P(x, y, dy=1.0): return (cx + x * u, cy + (y + dy) * u)

# Fundo: azul-noite com um brilho suave em cima à esquerda.
bg = Image.new("RGB", (S, S), (10, 13, 22))
glow = Image.new("RGB", (S, S), (0, 0, 0))
ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.35, S * 0.9, S * 0.75), fill=(30, 46, 90))
bg = Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(S * 0.12)), 0.6)

grad = Image.new("RGB", (S // 8, S // 8))
gp = grad.load()
for y in range(S // 8):
    for x in range(S // 8):
        gp[x, y] = lerp(sky, violet, min(1, max(0, (x + y) / (2 * S / 8))))
grad = grad.resize((S, S), Image.BILINEAR)

def rounded(mask, r):
    """Arredonda os cantos de uma máscara (desfoca e volta a cortar)."""
    return mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 128 else 0)

# Anel e setas.
R, w = 33 * u, 5.5 * u
ring = Image.new("L", (S, S), 0)
ImageDraw.Draw(ring).ellipse((cx - R, cy - R, cx + R, cy + R), outline=255, width=int(w))
arrows = Image.new("L", (S, S), 0)
ad = ImageDraw.Draw(arrows)
d, a, lw = 24.2 * u, 3.6 * u, int(2.2 * u)
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

# A cabeça da cabra, de frente.
goat = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(goat)
head = [(-7.6, -7), (7.6, -7), (9.2, -1.5), (7.2, 4.5), (4.2, 10.2), (0, 12.8), (-4.2, 10.2), (-7.2, 4.5), (-9.2, -1.5)]
gd.polygon([P(x, y) for x, y in head], fill=255)
gd.polygon([P(-2.3, 11.6), P(2.3, 11.6), P(0, 17.6)], fill=255)  # barbicha
def bezier(p0, p1, p2, n=80):
    for i in range(n + 1):
        t = i / n
        yield ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
               (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1], t)
for side in (-1, 1):
    # Chifres: saem do alto da testa, sobem e abrem para fora.
    for x, y, t in bezier((side * 4.4, -5.8), (side * 3.2, -20.5), (side * 12.8, -17.8)):
        r = (3.6 - 2.5 * t) * u
        X, Y = P(x, y)
        gd.ellipse((X - r, Y - r, X + r, Y + r), fill=255)
    # Orelhas: folhas deitadas para os lados.
    ear = []
    ex, ey, ang = side * 12.8, -1.2, math.radians(-14 * side)
    for i in range(48):
        th = 2 * math.pi * i / 48
        x0, y0 = 5.0 * math.cos(th), 1.9 * math.sin(th)
        ear.append(P(ex + x0 * math.cos(ang) - y0 * math.sin(ang), ey + x0 * math.sin(ang) + y0 * math.cos(ang)))
    gd.polygon(ear, fill=255)
goat = rounded(goat, 0.9 * u)

# Olhos e narinas (recortados).
holes = Image.new("L", (S, S), 0)
hd = ImageDraw.Draw(holes)
for side in (-1, 1):
    eye = []
    ex, ey, ang = side * 3.7, -0.6, math.radians(14 * side)
    for i in range(36):
        th = 2 * math.pi * i / 36
        x0, y0 = 1.5 * math.cos(th), 0.75 * math.sin(th)
        eye.append(P(ex + x0 * math.cos(ang) - y0 * math.sin(ang), ey + x0 * math.sin(ang) + y0 * math.cos(ang)))
    hd.polygon(eye, fill=255)
    nx, ny = P(side * 1.5, 9.4)
    hd.ellipse((nx - 0.65 * u, ny - 0.45 * u, nx + 0.65 * u, ny + 0.45 * u), fill=255)
goat.paste(0, (0, 0), holes)

img = bg.copy()
img.paste(grad, (0, 0), ring)
img.paste(grad, (0, 0), goat)
img.paste(Image.new("RGB", (S, S), (255, 255, 255)), (0, 0), arrows)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(out)
print("ok")
