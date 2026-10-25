# O ícone da app (1024×1024): python3 tools/icon/make-icon.py <saída.png>
# Precisa do Pillow. Anel e setas do comando com uma cabeça de cabra de perfil ao centro.
import sys, math
from PIL import Image, ImageDraw, ImageFilter
S = 4096
u = S / 100.0
out = sys.argv[1]
cx, cy = S / 2, S / 2
OX, OY = 0.5, 2.0  # desvio da cabeça (em u) para ficar centrada no anel
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
sky, violet = (56, 189, 248), (139, 92, 246)
def P(x, y): return (cx + (x + OX) * u, cy + (y + OY) * u)

def catmull(points, n=24):
    """Contorno suave fechado que passa por todos os pontos."""
    pts = []
    k = len(points)
    for i in range(k):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % k], points[(i + 2) % k]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            pts.append((x, y))
    return pts

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

R, w = 33 * u, 5.5 * u
ring = Image.new("L", (S, S), 0)
ImageDraw.Draw(ring).ellipse((cx - R, cy - R, cx + R, cy + R), outline=255, width=int(w))
arrows = Image.new("L", (S, S), 0)
ad = ImageDraw.Draw(arrows)
d, a, lw = 24.6 * u, 3.4 * u, int(2.1 * u)
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

# Cabeça de perfil, virada para a esquerda.
head = [(-14.0, 2.0), (-13.2, -1.2), (-9.5, -5.2), (-5.4, -8.6), (-1.2, -10.6), (3.0, -10.0), (6.4, -6.8),
        (8.2, -1.5), (9.0, 5.5), (10.2, 13.0), (2.0, 13.4), (-1.8, 8.4), (-5.6, 6.6), (-6.4, 9.5), (-7.2, 14.6),
        (-9.0, 9.0), (-10.4, 6.6), (-12.6, 5.6), (-14.2, 4.2)]
goat = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(goat)
gd.polygon([P(x, y) for x, y in catmull(head)], fill=255)
# Chifre: sai do alto da cabeça, sobe e curva para trás e para baixo, a afinar.
def cubic(p0, p1, p2, p3, n=120):
    for i in range(n + 1):
        t = i / n
        m = 1 - t
        yield (m ** 3 * p0[0] + 3 * m * m * t * p1[0] + 3 * m * t * t * p2[0] + t ** 3 * p3[0],
               m ** 3 * p0[1] + 3 * m * m * t * p1[1] + 3 * m * t * t * p2[1] + t ** 3 * p3[1], t)
for x, y, t in cubic((-0.6, -9.6), (0.2, -19.5), (10.5, -21.0), (13.6, -11.2)):
    r = (3.3 - 2.6 * t) * u
    X, Y = P(x, y)
    gd.ellipse((X - r, Y - r, X + r, Y + r), fill=255)
goat = goat.filter(ImageFilter.GaussianBlur(0.5 * u)).point(lambda v: 255 if v > 128 else 0)

# Recortes: separação entre o chifre e a orelha, olho, narina e boca.
cuts = Image.new("L", (S, S), 0)
cd = ImageDraw.Draw(cuts)
def ellipse(cx0, cy0, ax, by, deg, n=40):
    an = math.radians(deg)
    return [P(cx0 + ax * math.cos(2 * math.pi * i / n) * math.cos(an) - by * math.sin(2 * math.pi * i / n) * math.sin(an),
              cy0 + ax * math.cos(2 * math.pi * i / n) * math.sin(an) + by * math.sin(2 * math.pi * i / n) * math.cos(an)) for i in range(n)]
cd.polygon(ellipse(-5.0, -4.4, 1.45, 0.75, -18), fill=255)  # olho
cd.polygon(ellipse(-12.6, 1.3, 0.75, 0.45, -30), fill=255)  # narina
cd.line([P(-14.1, 4.3), P(-11.6, 4.7)], fill=255, width=int(0.55 * u))  # boca
# Linha fina a separar o chifre da cabeça.
for x, y, t in cubic((1.6, -9.0), (2.6, -15.0), (8.5, -16.6), (11.4, -11.6), 60):
    if t > 0.08:
        X, Y = P(x, y)
        rr = 0.35 * u
        cd.ellipse((X - rr, Y - rr, X + rr, Y + rr), fill=255)
goat.paste(0, (0, 0), cuts)
# Orelha, por cima, caída para trás.
ear = Image.new("L", (S, S), 0)
ImageDraw.Draw(ear).polygon(ellipse(7.6, -3.6, 4.8, 1.55, 24), fill=255)
earcut = Image.new("L", (S, S), 0)
ImageDraw.Draw(earcut).polygon(ellipse(7.6, -3.6, 5.25, 1.95, 24), fill=255)
goat.paste(0, (0, 0), earcut)
goat.paste(255, (0, 0), ear)

img = bg.copy()
img.paste(grad, (0, 0), ring)
img.paste(grad, (0, 0), goat)
img.paste(Image.new("RGB", (S, S), (255, 255, 255)), (0, 0), arrows)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(out)
print("ok")
